import Testing
import Foundation
import RealityKit
@testable import _D_Modeller
@testable import SwiftUIAssistant

// MARK: - Mock LLM Provider

/// A mock LLM provider for testing assistant integration
actor MockLLMProvider: LLMProvider {
    private var queuedResponses: [LLMResponse] = []
    private(set) var receivedMessages: [(message: String, systemPrompt: String)] = []
    private(set) var receivedToolSchemas: [[String: Any]] = []

    func queueResponse(_ response: LLMResponse) {
        queuedResponses.append(response)
    }

    func queueTextResponse(_ text: String) {
        queuedResponses.append(LLMResponse(
            content: text,
            toolCalls: nil,
            stopReason: .endTurn
        ))
    }

    func queueToolCallResponse(content: String?, toolCalls: [ToolCall]) {
        queuedResponses.append(LLMResponse(
            content: content,
            toolCalls: toolCalls,
            stopReason: .toolUse
        ))
    }

    func sendMessage(
        _ message: String,
        systemPrompt: String,
        conversationHistory: [Message],
        tools: [any AssistantTool]
    ) async throws -> LLMResponse {
        receivedMessages.append((message: message, systemPrompt: systemPrompt))

        guard !queuedResponses.isEmpty else {
            return LLMResponse(
                content: "Mock response (no queued responses)",
                toolCalls: nil,
                stopReason: .endTurn
            )
        }

        return queuedResponses.removeFirst()
    }
}

// MARK: - Test Context

@MainActor
struct TestSceneContext: AssistantContext {
    let sceneManager: SceneManager

    nonisolated func serialize() -> [String: JSONValue] {
        // Return empty for tests - context serialization is tested separately
        return [:]
    }

    nonisolated var contextDescription: String {
        "Test scene context"
    }
}

// MARK: - Assistant Integration Tests

@Suite("Assistant Integration Tests")
@MainActor
struct AssistantIntegrationTests {

    // MARK: - CreatePrimitiveTool Tests

    @Test("CreatePrimitiveTool creates a box")
    func testCreateBox() async throws {
        let sceneManager = SceneManager()
        let tool = CreatePrimitiveTool(sceneManager: sceneManager)

        let result = try await tool.execute(arguments: [
            "type": .string("box"),
            "name": .string("TestBox"),
            "position": .object(["x": .number(1), "y": .number(2), "z": .number(3)]),
            "size": .number(0.5),
            "color": .string("red")
        ])

        #expect(result.success)
        #expect(result.message.contains("Created box"))
        #expect(sceneManager.entities.count == 1)

        let entity = sceneManager.entities.values.first
        #expect(entity?.name == "TestBox")
        #expect(entity?.type == .box)
    }

    @Test("CreatePrimitiveTool creates a sphere at origin")
    func testCreateSphereAtOrigin() async throws {
        let sceneManager = SceneManager()
        let tool = CreatePrimitiveTool(sceneManager: sceneManager)

        let result = try await tool.execute(arguments: [
            "type": .string("sphere")
        ])

        #expect(result.success)
        #expect(sceneManager.entities.count == 1)

        let entity = sceneManager.entities.values.first
        #expect(entity?.type == .sphere)
        #expect(entity?.entity.position.x == 0)
        #expect(entity?.entity.position.y == 0)
        #expect(entity?.entity.position.z == 0)
    }

    @Test("CreatePrimitiveTool fails with invalid type")
    func testCreateInvalidType() async throws {
        let sceneManager = SceneManager()
        let tool = CreatePrimitiveTool(sceneManager: sceneManager)

        let result = try await tool.execute(arguments: [
            "type": .string("invalid")
        ])

        #expect(!result.success)
        #expect(result.message.contains("Invalid"))
        #expect(sceneManager.entities.isEmpty)
    }

    @Test("CreatePrimitiveTool fails with missing type")
    func testCreateMissingType() async throws {
        let sceneManager = SceneManager()
        let tool = CreatePrimitiveTool(sceneManager: sceneManager)

        let result = try await tool.execute(arguments: [:])

        #expect(!result.success)
        #expect(sceneManager.entities.isEmpty)
    }

    // MARK: - QuerySceneTool Tests

    @Test("QuerySceneTool returns empty scene info")
    func testQueryEmptyScene() async throws {
        let sceneManager = SceneManager()
        let tool = QuerySceneTool(sceneManager: sceneManager)

        let result = try await tool.execute(arguments: [:])

        #expect(result.success)
        #expect(result.message.contains("empty"))
    }

    @Test("QuerySceneTool returns entities")
    func testQueryWithEntities() async throws {
        let sceneManager = SceneManager()
        _ = sceneManager.createPrimitive(type: .box, name: "Box1")
        _ = sceneManager.createPrimitive(type: .sphere, name: "Sphere1")

        let tool = QuerySceneTool(sceneManager: sceneManager)
        let result = try await tool.execute(arguments: [:])

        #expect(result.success)
        #expect(result.message.contains("2 entities"))
        #expect(result.data?["entities"]?.arrayValue?.count == 2)
    }

    @Test("QuerySceneTool filters by type")
    func testQueryFilterByType() async throws {
        let sceneManager = SceneManager()
        _ = sceneManager.createPrimitive(type: .box, name: "Box1")
        _ = sceneManager.createPrimitive(type: .box, name: "Box2")
        _ = sceneManager.createPrimitive(type: .sphere, name: "Sphere1")

        let tool = QuerySceneTool(sceneManager: sceneManager)
        let result = try await tool.execute(arguments: [
            "type": .string("box")
        ])

        #expect(result.success)
        #expect(result.message.contains("2 entities"))
    }

    @Test("QuerySceneTool filters by name")
    func testQueryFilterByName() async throws {
        let sceneManager = SceneManager()
        _ = sceneManager.createPrimitive(type: .box, name: "RedBox")
        _ = sceneManager.createPrimitive(type: .box, name: "BlueBox")
        _ = sceneManager.createPrimitive(type: .sphere, name: "Sphere")

        let tool = QuerySceneTool(sceneManager: sceneManager)
        let result = try await tool.execute(arguments: [
            "filter": .string("Box")
        ])

        #expect(result.success)
        #expect(result.message.contains("2 entities"))
    }

    // MARK: - TransformEntityTool Tests

    @Test("TransformEntityTool moves entity")
    func testTransformPosition() async throws {
        let sceneManager = SceneManager()
        _ = sceneManager.createPrimitive(type: .box, name: "TestBox")

        let tool = TransformEntityTool(sceneManager: sceneManager)
        let result = try await tool.execute(arguments: [
            "entityName": .string("TestBox"),
            "position": .object(["x": .number(5), "y": .number(0), "z": .number(0)])
        ])

        #expect(result.success)
        #expect(result.message.contains("position"))

        let entity = sceneManager.entity(named: "TestBox")
        #expect(entity?.entity.position.x == 5)
    }

    @Test("TransformEntityTool fails for non-existent entity")
    func testTransformNonExistent() async throws {
        let sceneManager = SceneManager()
        let tool = TransformEntityTool(sceneManager: sceneManager)

        let result = try await tool.execute(arguments: [
            "entityName": .string("NoSuchEntity"),
            "position": .object(["x": .number(1), "y": .number(0), "z": .number(0)])
        ])

        #expect(!result.success)
        #expect(result.message.contains("not found"))
    }

    // MARK: - DeleteEntityTool Tests

    @Test("DeleteEntityTool removes entity")
    func testDeleteEntity() async throws {
        let sceneManager = SceneManager()
        _ = sceneManager.createPrimitive(type: .box, name: "ToDelete")
        #expect(sceneManager.entities.count == 1)

        let tool = DeleteEntityTool(sceneManager: sceneManager)
        let result = try await tool.execute(arguments: [
            "entityName": .string("ToDelete")
        ])

        #expect(result.success)
        #expect(sceneManager.entities.isEmpty)
    }

    @Test("DeleteEntityTool fails for non-existent entity")
    func testDeleteNonExistent() async throws {
        let sceneManager = SceneManager()
        let tool = DeleteEntityTool(sceneManager: sceneManager)

        let result = try await tool.execute(arguments: [
            "entityName": .string("NoSuchEntity")
        ])

        #expect(!result.success)
        #expect(result.message.contains("not found"))
    }

    // MARK: - Full Assistant Flow Tests

    @Test("Assistant creates primitive via tool call")
    func testAssistantCreatesPrimitive() async throws {
        let sceneManager = SceneManager()
        let provider = MockLLMProvider()

        // Queue: first response has tool call, second is final text
        let toolCall = ToolCall(
            id: "call_1",
            name: "create_primitive",
            arguments: [
                "type": .string("sphere"),
                "name": .string("MySphere"),
                "color": .string("blue")
            ]
        )
        await provider.queueToolCallResponse(content: nil, toolCalls: [toolCall])
        await provider.queueTextResponse("I created a blue sphere called MySphere for you.")

        let tools: [any AssistantTool] = [
            CreatePrimitiveTool(sceneManager: sceneManager),
            QuerySceneTool(sceneManager: sceneManager)
        ]

        let assistant = Assistant(
            provider: provider,
            tools: tools,
            contextProvider: { TestSceneContext(sceneManager: sceneManager) }
        )

        try await assistant.send("Create a blue sphere")

        // Verify entity was created
        #expect(sceneManager.entities.count == 1)
        let entity = sceneManager.entities.values.first
        #expect(entity?.name == "MySphere")
        #expect(entity?.type == .sphere)

        // Verify conversation has messages
        #expect(assistant.messages.count >= 2)
    }

    @Test("Assistant executes multiple tool calls in sequence")
    func testAssistantMultipleToolCalls() async throws {
        let sceneManager = SceneManager()
        let provider = MockLLMProvider()

        // First: create a box
        let createCall = ToolCall(
            id: "call_1",
            name: "create_primitive",
            arguments: [
                "type": .string("box"),
                "name": .string("MyBox")
            ]
        )
        await provider.queueToolCallResponse(content: nil, toolCalls: [createCall])

        // Second: query the scene
        let queryCall = ToolCall(
            id: "call_2",
            name: "query_scene",
            arguments: [:]
        )
        await provider.queueToolCallResponse(content: nil, toolCalls: [queryCall])

        // Final response
        await provider.queueTextResponse("Created a box and verified it's in the scene.")

        let tools: [any AssistantTool] = [
            CreatePrimitiveTool(sceneManager: sceneManager),
            QuerySceneTool(sceneManager: sceneManager)
        ]

        let assistant = Assistant(
            provider: provider,
            tools: tools,
            contextProvider: { TestSceneContext(sceneManager: sceneManager) }
        )

        try await assistant.send("Create a box and verify it exists")

        #expect(sceneManager.entities.count == 1)
    }

    @Test("Assistant handles tool failure gracefully")
    func testAssistantHandlesToolFailure() async throws {
        let sceneManager = SceneManager()
        let provider = MockLLMProvider()

        // Try to transform non-existent entity
        let toolCall = ToolCall(
            id: "call_1",
            name: "transform_entity",
            arguments: [
                "entityName": .string("NonExistent"),
                "position": .object(["x": .number(1), "y": .number(0), "z": .number(0)])
            ]
        )
        await provider.queueToolCallResponse(content: nil, toolCalls: [toolCall])
        await provider.queueTextResponse("I couldn't find that entity. Please create it first.")

        let tools: [any AssistantTool] = [
            TransformEntityTool(sceneManager: sceneManager)
        ]

        let assistant = Assistant(
            provider: provider,
            tools: tools,
            contextProvider: { TestSceneContext(sceneManager: sceneManager) }
        )

        // Should not throw
        try await assistant.send("Move the box")

        // Conversation should have continued
        #expect(assistant.messages.count >= 2)
    }

    @Test("Assistant context is provided to LLM")
    func testAssistantContextProvided() async throws {
        let sceneManager = SceneManager()
        _ = sceneManager.createPrimitive(type: .box, name: "TestBox")

        let provider = MockLLMProvider()
        await provider.queueTextResponse("I can see you have a box.")

        let assistant = Assistant(
            provider: provider,
            tools: [],
            contextProvider: { TestSceneContext(sceneManager: sceneManager) }
        )

        try await assistant.send("What's in my scene?")

        let received = await provider.receivedMessages
        // Verify the provider received a message with a system prompt
        #expect(received.first?.systemPrompt.isEmpty == false)
    }

    @Test("Assistant create and delete workflow")
    func testCreateAndDeleteWorkflow() async throws {
        let sceneManager = SceneManager()
        let provider = MockLLMProvider()

        // Create
        let createCall = ToolCall(
            id: "call_1",
            name: "create_primitive",
            arguments: ["type": .string("cylinder"), "name": .string("Temp")]
        )
        await provider.queueToolCallResponse(content: nil, toolCalls: [createCall])

        // Delete
        let deleteCall = ToolCall(
            id: "call_2",
            name: "delete_entity",
            arguments: ["entityName": .string("Temp")]
        )
        await provider.queueToolCallResponse(content: nil, toolCalls: [deleteCall])

        await provider.queueTextResponse("Created and deleted the cylinder.")

        let tools: [any AssistantTool] = [
            CreatePrimitiveTool(sceneManager: sceneManager),
            DeleteEntityTool(sceneManager: sceneManager)
        ]

        let assistant = Assistant(
            provider: provider,
            tools: tools,
            contextProvider: { TestSceneContext(sceneManager: sceneManager) }
        )

        try await assistant.send("Create a cylinder then delete it")

        #expect(sceneManager.entities.isEmpty)
    }

    // MARK: - Tool Parameter Validation Tests

    @Test("CreatePrimitiveTool validates color names")
    func testColorNameValidation() async throws {
        let sceneManager = SceneManager()
        let tool = CreatePrimitiveTool(sceneManager: sceneManager)

        // Valid color
        let result = try await tool.execute(arguments: [
            "type": .string("box"),
            "color": .string("red")
        ])
        #expect(result.success)

        // Invalid color falls back to default (doesn't fail)
        let result2 = try await tool.execute(arguments: [
            "type": .string("sphere"),
            "color": .string("notacolor")
        ])
        #expect(result2.success)
    }

    @Test("All primitive types can be created")
    func testAllPrimitiveTypes() async throws {
        let sceneManager = SceneManager()
        let tool = CreatePrimitiveTool(sceneManager: sceneManager)

        let types = ["box", "sphere", "cylinder", "cone", "plane", "torus"]

        for typeName in types {
            let result = try await tool.execute(arguments: [
                "type": .string(typeName),
                "name": .string("\(typeName)_test")
            ])
            #expect(result.success, "Failed to create \(typeName)")
        }

        #expect(sceneManager.entities.count == types.count)
    }
}
