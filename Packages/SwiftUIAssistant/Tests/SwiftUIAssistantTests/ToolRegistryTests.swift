import Testing
import Foundation
@testable import SwiftUIAssistant

@Suite("ToolRegistry Tests")
struct ToolRegistryTests {

    @Test("Register and retrieve tool")
    func testRegisterAndRetrieve() {
        let registry = ToolRegistry()
        let tool = MockTool(
            id: "test_tool",
            name: "test_tool",
            description: "A test tool"
        )

        registry.register(tool)

        let retrieved = registry.tool(named: "test_tool")
        #expect(retrieved != nil)
        #expect(retrieved?.name == "test_tool")
    }

    @Test("List all registered tools")
    func testListAllTools() {
        let registry = ToolRegistry()

        registry.register(MockTool(id: "tool_1", name: "tool_1", description: "First"))
        registry.register(MockTool(id: "tool_2", name: "tool_2", description: "Second"))
        registry.register(MockTool(id: "tool_3", name: "tool_3", description: "Third"))

        let allTools = registry.allTools
        #expect(allTools.count == 3)
    }

    @Test("Retrieve non-existent tool returns nil")
    func testNonExistentTool() {
        let registry = ToolRegistry()

        let tool = registry.tool(named: "non_existent")
        #expect(tool == nil)
    }

    @Test("Register multiple tools with same name replaces")
    func testDuplicateRegistration() {
        let registry = ToolRegistry()

        let tool1 = MockTool(id: "tool_1", name: "same_name", description: "First version")
        let tool2 = MockTool(id: "tool_2", name: "same_name", description: "Second version")

        registry.register(tool1)
        registry.register(tool2)

        let retrieved = registry.tool(named: "same_name")
        #expect(retrieved?.description == "Second version")
        #expect(registry.allTools.count == 1)
    }

    @Test("Unregister tool")
    func testUnregisterTool() {
        let registry = ToolRegistry()
        let tool = MockTool(id: "tool_1", name: "tool_1", description: "Test")

        registry.register(tool)
        #expect(registry.tool(named: "tool_1") != nil)

        registry.unregister(named: "tool_1")
        #expect(registry.tool(named: "tool_1") == nil)
    }

    @Test("Generate tool schemas for LLM")
    func testGenerateSchemas() {
        let registry = ToolRegistry()

        let tool = MockTool(
            id: "create_object",
            name: "create_object",
            description: "Creates a new object",
            parameters: [
                ToolParameter(name: "type", type: .string, description: "Object type", required: true),
                ToolParameter(name: "color", type: .string, description: "Object color", required: false)
            ]
        )

        registry.register(tool)

        let schemas = registry.toolSchemas()
        #expect(schemas.count == 1)

        let schema = schemas.first!
        #expect(schema["name"] as? String == "create_object")
        #expect(schema["description"] as? String == "Creates a new object")
    }
}
