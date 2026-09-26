import Foundation

/// Represents a message in the conversation
public struct Message: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?
    /// Provider-native content blocks, replayed verbatim on the next request
    public let rawContent: [JSONValue]?
    public let timestamp: Date

    /// The role of the message sender
    public enum Role: String, Sendable, Equatable {
        case system
        case user
        case assistant
        case toolResult = "tool_result"
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        rawContent: [JSONValue]? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.rawContent = rawContent
        self.timestamp = timestamp
    }

    // MARK: - Convenience Initializers

    /// Create a user message
    public static func user(_ content: String) -> Message {
        Message(role: .user, content: content)
    }

    /// Create an assistant message
    public static func assistant(
        _ content: String,
        toolCalls: [ToolCall]? = nil,
        rawContent: [JSONValue]? = nil
    ) -> Message {
        Message(role: .assistant, content: content, toolCalls: toolCalls, rawContent: rawContent)
    }

    /// Create a system message
    public static func system(_ content: String) -> Message {
        Message(role: .system, content: content)
    }

    /// Create a tool result message
    public static func toolResult(toolCallId: String, content: String) -> Message {
        Message(role: .toolResult, content: content, toolCallId: toolCallId)
    }
}
