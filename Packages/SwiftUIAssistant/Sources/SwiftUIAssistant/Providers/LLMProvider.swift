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
}
