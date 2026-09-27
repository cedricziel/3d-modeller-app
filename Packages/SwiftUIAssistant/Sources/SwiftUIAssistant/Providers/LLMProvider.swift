import Foundation

/// Protocol for LLM providers (Claude, OpenAI, etc.)
public protocol LLMProvider: Sendable {
    /// Send a message to the LLM and receive a response
    /// - Parameters:
    ///   - message: The user's message
    ///   - systemPrompt: The system prompt to use
    ///   - conversationHistory: Previous messages in the conversation
    ///   - tools: Available tools the LLM can use
    /// - Returns: The LLM's response
    func sendMessage(
        _ message: String,
        systemPrompt: String,
        conversationHistory: [Message],
        tools: [any AssistantTool]
    ) async throws -> LLMResponse

    /// Send a message and report the reply as it is generated
    ///
    /// `onEvent` is awaited for each event, in order, before the provider reads further. The returned
    /// response is the complete turn; tool calls appear only there, once their input is complete.
    /// Providers that cannot stream get a default that calls `sendMessage` and reports no events.
    func streamMessage(
        _ message: String,
        systemPrompt: String,
        conversationHistory: [Message],
        tools: [any AssistantTool],
        onEvent: @escaping @Sendable (LLMStreamEvent) async -> Void
    ) async throws -> LLMResponse
}

/// A piece of a reply that is still being generated
public enum LLMStreamEvent: Sendable, Equatable {
    /// The model is thinking; the text is empty when the provider does not show its reasoning
    case thinking(String)
    /// Text to append to the reply
    case text(String)
}

extension LLMProvider {
    public func streamMessage(
        _ message: String,
        systemPrompt: String,
        conversationHistory: [Message],
        tools: [any AssistantTool],
        onEvent: @escaping @Sendable (LLMStreamEvent) async -> Void
    ) async throws -> LLMResponse {
        try await sendMessage(
            message, systemPrompt: systemPrompt, conversationHistory: conversationHistory, tools: tools)
    }
}
