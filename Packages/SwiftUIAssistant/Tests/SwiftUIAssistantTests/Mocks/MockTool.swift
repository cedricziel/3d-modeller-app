import Foundation
@testable import SwiftUIAssistant

/// A mock implementation of AssistantTool for testing
struct MockTool: AssistantTool {
    let id: String
    let name: String
    let description: String
    var parameters: [ToolParameter]

    /// Closure to customize execution behavior in tests
    var executeHandler: (([String: Any]) async throws -> ToolExecutionResult)?

    init(
        id: String,
        name: String,
        description: String,
        parameters: [ToolParameter] = [],
        executeHandler: (([String: Any]) async throws -> ToolExecutionResult)? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.parameters = parameters
        self.executeHandler = executeHandler
    }

    func execute(arguments: [String: Any]) async throws -> ToolExecutionResult {
        if let handler = executeHandler {
            return try await handler(arguments)
        }

        // Default success response
        return ToolExecutionResult(
            success: true,
            message: "Mock tool '\(name)' executed successfully",
            data: ["arguments": arguments]
        )
    }
}

/// A mock tool that always fails
struct FailingMockTool: AssistantTool {
    let id: String = "failing_tool"
    let name: String = "failing_tool"
    let description: String = "A tool that always fails"
    let parameters: [ToolParameter] = []

    let errorMessage: String

    init(errorMessage: String = "Mock failure") {
        self.errorMessage = errorMessage
    }

    func execute(arguments: [String: Any]) async throws -> ToolExecutionResult {
        return ToolExecutionResult(
            success: false,
            message: errorMessage,
            data: nil
        )
    }
}

/// A mock tool that throws an error
struct ThrowingMockTool: AssistantTool {
    let id: String = "throwing_tool"
    let name: String = "throwing_tool"
    let description: String = "A tool that throws"
    let parameters: [ToolParameter] = []

    func execute(arguments: [String: Any]) async throws -> ToolExecutionResult {
        throw AssistantError.toolExecutionFailed(toolName: name, reason: "Intentional test error")
    }
}

/// A mock tool with a delay for testing async behavior
struct DelayedMockTool: AssistantTool {
    let id: String = "delayed_tool"
    let name: String = "delayed_tool"
    let description: String = "A tool with artificial delay"
    let parameters: [ToolParameter] = []

    let delayNanoseconds: UInt64

    init(delaySeconds: Double = 0.1) {
        self.delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
    }

    func execute(arguments: [String: Any]) async throws -> ToolExecutionResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return ToolExecutionResult(
            success: true,
            message: "Delayed execution complete",
            data: nil
        )
    }
}
