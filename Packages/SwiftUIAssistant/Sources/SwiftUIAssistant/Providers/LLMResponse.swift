import Foundation

/// Response from an LLM provider
public struct LLMResponse: Sendable {
    /// Text content of the response
    public let content: String?

    /// Tool calls requested by the LLM
    public let toolCalls: [ToolCall]?

    /// Why the LLM stopped generating
    public let stopReason: StopReason

    /// Usage statistics (optional)
    public let usage: Usage?

    /// Provider-native content blocks, kept so they can be sent back unchanged
    public let rawContent: [JSONValue]?

    /// Reason the LLM stopped generating
    public enum StopReason: String, Sendable {
        case endTurn = "end_turn"
        case toolUse = "tool_use"
        case maxTokens = "max_tokens"
        case stopSequence = "stop_sequence"
        case refusal
    }

    /// Token usage statistics
    public struct Usage: Sendable {
        public let inputTokens: Int
        public let outputTokens: Int

        public init(inputTokens: Int, outputTokens: Int) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }
    }

    public init(
        content: String?,
        toolCalls: [ToolCall]?,
        stopReason: StopReason,
        usage: Usage? = nil,
        rawContent: [JSONValue]? = nil
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.stopReason = stopReason
        self.usage = usage
        self.rawContent = rawContent
    }

    /// Whether this response contains tool calls that need execution
    public var hasToolCalls: Bool {
        guard let calls = toolCalls else { return false }
        return !calls.isEmpty
    }
}
