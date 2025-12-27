import Testing
import Foundation
@testable import SwiftUIAssistant

@Suite("ToolCall Tests")
struct ToolCallTests {

    @Test("ToolCall creation with arguments")
    func testToolCallCreation() {
        let toolCall = ToolCall(
            id: "call_abc123",
            name: "transform_entity",
            arguments: [
                "entityName": "Cube",
                "position": [1.0, 2.0, 3.0]
            ]
        )

        #expect(toolCall.id == "call_abc123")
        #expect(toolCall.name == "transform_entity")
        #expect(toolCall.arguments["entityName"] as? String == "Cube")
    }

    @Test("ToolCall status transitions")
    func testToolCallStatusTransitions() {
        var toolCall = ToolCall(
            id: "call_123",
            name: "delete_entity",
            arguments: ["entityName": "Sphere"]
        )

        #expect(toolCall.status == .pending)

        toolCall.status = .executing
        #expect(toolCall.status == .executing)

        toolCall.status = .completed
        #expect(toolCall.status == .completed)
    }

    @Test("ToolCall with result")
    func testToolCallWithResult() {
        var toolCall = ToolCall(
            id: "call_123",
            name: "create_primitive",
            arguments: ["type": "sphere"]
        )

        let result = ToolExecutionResult(
            success: true,
            message: "Created sphere 'Sphere_1'",
            data: ["entityId": "entity_456"]
        )

        toolCall.result = result
        toolCall.status = .completed

        #expect(toolCall.result?.success == true)
        #expect(toolCall.result?.message == "Created sphere 'Sphere_1'")
    }

    @Test("ToolCall failed status")
    func testToolCallFailed() {
        var toolCall = ToolCall(
            id: "call_123",
            name: "delete_entity",
            arguments: ["entityName": "NonExistent"]
        )

        let result = ToolExecutionResult(
            success: false,
            message: "Entity 'NonExistent' not found",
            data: nil
        )

        toolCall.result = result
        toolCall.status = .failed

        #expect(toolCall.status == .failed)
        #expect(toolCall.result?.success == false)
    }
}
