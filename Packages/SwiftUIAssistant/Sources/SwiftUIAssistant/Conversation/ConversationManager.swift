import Foundation

/// Manages conversation history and state
@MainActor
public final class ConversationManager: ObservableObject {
    /// All messages in the conversation
    @Published public private(set) var messages: [Message] = []

    public init() {}

    // MARK: - Message Management

    /// Add a user message
    public func addUserMessage(_ content: String) {
        let message = Message(role: .user, content: content)
        messages.append(message)
    }

    /// Add an assistant message
    public func addAssistantMessage(_ content: String, toolCalls: [ToolCall]? = nil) {
        let message = Message(role: .assistant, content: content, toolCalls: toolCalls)
        messages.append(message)
    }

    /// Add a system message
    public func addSystemMessage(_ content: String) {
        let message = Message(role: .system, content: content)
        messages.append(message)
    }

    /// Add a tool result message
    public func addToolResult(toolCallId: String, result: ToolExecutionResult) {
        let message = Message(
            role: .toolResult,
            content: result.toPromptString(),
            toolCallId: toolCallId
        )
        messages.append(message)
    }

    /// Add a raw message
    public func add(_ message: Message) {
        messages.append(message)
    }

    /// Clear all messages
    public func clear() {
        messages.removeAll()
    }

    // MARK: - Accessors

    /// Get conversation history (for sending to LLM)
    public var history: [Message] {
        messages
    }

    /// Get the last message
    public var lastMessage: Message? {
        messages.last
    }

    /// Get messages by role
    public func messages(withRole role: Message.Role) -> [Message] {
        messages.filter { $0.role == role }
    }

    // MARK: - Utility

    /// Get the count of messages
    public var count: Int {
        messages.count
    }

    /// Check if conversation is empty
    public var isEmpty: Bool {
        messages.isEmpty
    }
}
