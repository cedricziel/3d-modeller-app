import Foundation
import SwiftUI

/// The main assistant class that orchestrates LLM interactions and tool execution
@MainActor
public final class Assistant: ObservableObject {
    // MARK: - Published State

    /// All messages in the conversation
    @Published public private(set) var messages: [Message] = []

    /// Whether the assistant is currently processing a request
    @Published public private(set) var isProcessing: Bool = false

    /// The current error, if any
    @Published public private(set) var currentError: AssistantError?

    /// The reply the model is still generating, until its turn is complete
    @Published public private(set) var streamingReply: StreamingReply?

    // MARK: - Dependencies

    private let provider: any LLMProvider
    private let toolRegistry: ToolRegistry
    private let contextProvider: @Sendable () -> any AssistantContext
    private let configuration: AssistantConfiguration

    /// Built on the first request and reused until the history is cleared, because
    /// models that replay thinking reject a system prompt that changes mid-conversation
    private var conversationSystemPrompt: String?

    // MARK: - Initialization

    /// Create a new assistant
    /// - Parameters:
    ///   - provider: The LLM provider to use
    ///   - tools: Available tools the assistant can use
    ///   - contextProvider: Closure that returns the current context
    ///   - configuration: Configuration options
    public init(
        provider: any LLMProvider,
        tools: [any AssistantTool],
        contextProvider: @escaping @Sendable () -> any AssistantContext,
        configuration: AssistantConfiguration = .default
    ) {
        self.provider = provider
        self.toolRegistry = ToolRegistry(tools: tools)
        self.contextProvider = contextProvider
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Send a message and process the response
    /// - Parameter message: The user's message
    public func send(_ message: String) async throws {
        guard !isProcessing else { return }

        isProcessing = true
        currentError = nil

        defer { isProcessing = false }

        // Add user message
        let context = configuration.attachesContextToMessages ? contextProvider().contextDescription : nil
        messages.append(Message.user(message, context: context))

        // Process response (may involve multiple tool execution rounds)
        try await processResponse()
    }

    /// Clear the conversation history
    public func clearHistory() {
        messages.removeAll()
        conversationSystemPrompt = nil
        currentError = nil
    }

    /// Register additional tools
    public func registerTool(_ tool: any AssistantTool) {
        toolRegistry.register(tool)
    }

    // MARK: - Private Implementation

    private func processResponse() async throws {
        var rounds = 0

        while rounds < configuration.maxToolExecutionRounds {
            rounds += 1

            let systemPrompt =
                conversationSystemPrompt
                ?? configuration.buildSystemPrompt(context: contextProvider())
            conversationSystemPrompt = systemPrompt

            streamingReply = StreamingReply()
            defer { streamingReply = nil }
            let response = try await provider.streamMessage(
                messages.last?.content ?? "",
                systemPrompt: systemPrompt,
                conversationHistory: messages,
                tools: toolRegistry.allTools
            ) { [weak self] event in
                await self?.apply(event)
            }
            streamingReply = nil

            // Add assistant message if there's content
            if let content = response.content {
                messages.append(
                    Message.assistant(content, toolCalls: response.toolCalls, rawContent: response.rawContent))
            } else if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                // Tool calls without text content
                messages.append(Message.assistant("", toolCalls: toolCalls, rawContent: response.rawContent))
            }

            // Execute tool calls if present
            if response.hasToolCalls, let toolCalls = response.toolCalls {
                for toolCall in toolCalls {
                    let result = await executeToolCall(toolCall)
                    messages.append(
                        Message.toolResult(
                            toolCallId: toolCall.id, content: result.toPromptString(), images: result.images))
                }

                // Continue to get LLM's response after tool execution
                continue
            }

            // No more tool calls, we're done
            break
        }
    }

    private func apply(_ event: LLMStreamEvent) {
        guard var reply = streamingReply else { return }
        switch event {
        case .thinking:
            reply.isThinking = true
        case .text(let text):
            reply.text += text
            reply.isThinking = false
        }
        streamingReply = reply
    }

    private func executeToolCall(_ toolCall: ToolCall) async -> ToolExecutionResult {
        guard let tool = toolRegistry.tool(named: toolCall.name) else {
            return .failure("Tool '\(toolCall.name)' not found")
        }

        do {
            return try await tool.execute(arguments: toolCall.arguments)
        } catch let error as AssistantError {
            currentError = error
            return .failure(error.localizedDescription)
        } catch {
            let assistantError = AssistantError.toolExecutionFailed(
                toolName: toolCall.name,
                reason: error.localizedDescription
            )
            currentError = assistantError
            return .failure(error.localizedDescription)
        }
    }
}

/// The part of a reply that has arrived so far
public struct StreamingReply: Equatable, Sendable {
    public var text: String
    /// Whether the model is thinking rather than writing
    public var isThinking: Bool

    public init(text: String = "", isThinking: Bool = false) {
        self.text = text
        self.isThinking = isThinking
    }
}
