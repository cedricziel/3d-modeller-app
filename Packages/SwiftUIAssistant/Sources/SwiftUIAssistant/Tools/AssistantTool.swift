import Foundation

/// A tool that the assistant can execute autonomously
public protocol AssistantTool: Identifiable, Sendable {
    /// Unique identifier for the tool
    var id: String { get }

    /// The name used to invoke the tool (must match what LLM uses)
    var name: String { get }

    /// Human-readable description of what the tool does
    var description: String { get }

    /// Parameters the tool accepts
    var parameters: [ToolParameter] { get }

    /// Execute the tool with the given arguments
    /// - Parameter arguments: Dictionary of argument name to value
    /// - Returns: The result of the execution
    func execute(arguments: [String: Any]) async throws -> ToolExecutionResult
}

// MARK: - Default Implementations

public extension AssistantTool {
    /// Default id is the name
    var id: String { name }

    /// Default empty parameters
    var parameters: [ToolParameter] { [] }
}
