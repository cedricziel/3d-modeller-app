import Foundation

/// The result of executing a tool
public struct ToolExecutionResult: Sendable, Equatable {
    /// Whether the tool execution succeeded
    public let success: Bool

    /// A human-readable message describing the result
    public let message: String

    /// Optional additional data from the execution
    public let data: [String: JSONValue]?

    public init(
        success: Bool,
        message: String,
        data: [String: JSONValue]? = nil
    ) {
        self.success = success
        self.message = message
        self.data = data
    }

    // MARK: - Convenience Initializers

    /// Create a successful result
    public static func success(_ message: String, data: [String: JSONValue]? = nil) -> ToolExecutionResult {
        ToolExecutionResult(success: true, message: message, data: data)
    }

    /// Create a failure result
    public static func failure(_ message: String) -> ToolExecutionResult {
        ToolExecutionResult(success: false, message: message, data: nil)
    }

    // MARK: - Serialization

    /// Convert to a string format suitable for sending back to the LLM
    public func toPromptString() -> String {
        if success {
            return "Success: \(message)"
        } else {
            return "Error: \(message)"
        }
    }
}
