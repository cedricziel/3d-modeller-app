import Foundation

/// Represents a tool invocation requested by the LLM
public struct ToolCall: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let arguments: [String: Any]
    public var status: Status
    public var result: ToolExecutionResult?

    /// The execution status of the tool call
    public enum Status: String, Sendable, Equatable {
        case pending
        case executing
        case completed
        case failed
    }

    public init(
        id: String,
        name: String,
        arguments: [String: Any],
        status: Status = .pending,
        result: ToolExecutionResult? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.status = status
        self.result = result
    }

    // MARK: - Equatable

    public static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.status == rhs.status
        // Note: arguments comparison is omitted due to [String: Any]
    }
}
