import Foundation
@testable import SwiftUIAssistant

/// A mock LLM provider for testing
actor MockLLMProvider: LLMProvider {
    /// Responses to return in order
    private var queuedResponses: [LLMResponse] = []

    /// All messages received by this provider
    private(set) var receivedMessages: [(message: String, systemPrompt: String)] = []

    /// Delay before responding (for testing async behavior)
    var responseDelay: UInt64 = 0

    /// Whether to throw an error on next call
    var shouldThrowError: Error?

    init() {}

    /// Queue a response to be returned on next sendMessage call
    func queueResponse(_ response: LLMResponse) {
        queuedResponses.append(response)
    }

    /// Queue a simple text response
    func queueTextResponse(_ text: String) {
        queuedResponses.append(LLMResponse(
            content: text,
            toolCalls: nil,
            stopReason: .endTurn
        ))
    }

    /// Queue a response with tool calls
    func queueToolCallResponse(content: String?, toolCalls: [ToolCall]) {
        queuedResponses.append(LLMResponse(
            content: content,
            toolCalls: toolCalls,
            stopReason: .toolUse
        ))
    }

    func sendMessage(
        _ message: String,
        systemPrompt: String,
        conversationHistory: [Message],
        tools: [any AssistantTool]
    ) async throws -> LLMResponse {
        receivedMessages.append((message: message, systemPrompt: systemPrompt))

        if responseDelay > 0 {
            try await Task.sleep(nanoseconds: responseDelay)
        }

        if let error = shouldThrowError {
            throw error
        }

        guard !queuedResponses.isEmpty else {
            return LLMResponse(
                content: "Mock response",
                toolCalls: nil,
                stopReason: .endTurn
            )
        }

        return queuedResponses.removeFirst()
    }
}

/// A mock LLM provider that simulates streaming responses
actor StreamingMockLLMProvider: LLMProvider {
    var chunks: [String] = []

    func sendMessage(
        _ message: String,
        systemPrompt: String,
        conversationHistory: [Message],
        tools: [any AssistantTool]
    ) async throws -> LLMResponse {
        // Simulate streaming by returning concatenated chunks
        let fullContent = chunks.joined()
        return LLMResponse(
            content: fullContent,
            toolCalls: nil,
            stopReason: .endTurn
        )
    }
}
