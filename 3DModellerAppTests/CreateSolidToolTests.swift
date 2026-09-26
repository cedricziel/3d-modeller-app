import SwiftUIAssistant
import Testing
@testable import _D_Modeller

@Suite("CreateSolidTool")
@MainActor
struct CreateSolidToolTests {
    @Test("Creates a rounded block from the assistant's arguments")
    func createsBlock() async throws {
        let scene = SceneManager()
        let tool = CreateSolidTool(sceneManager: scene)

        let result = try await tool.execute(arguments: [
            "name": .string("Bracket"),
            "width": .number(0.4),
            "height": .number(0.2),
            "depth": .number(0.1),
            "fillet_radius": .number(0.02),
            "color": .string("blue"),
        ])

        #expect(result.success)
        let entity = try #require(scene.entity(named: "Bracket"))
        #expect(entity.solid == SolidRecipe(width: 0.4, height: 0.2, depth: 0.1, filletRadius: 0.02))
        #expect(scene.selectedEntityId == entity.id)
    }

    @Test("Missing dimensions fail without touching the scene")
    func missingDimensions() async throws {
        let scene = SceneManager()
        let tool = CreateSolidTool(sceneManager: scene)

        let result = try await tool.execute(arguments: ["width": .number(0.4)])

        #expect(!result.success)
        #expect(result.message.contains("height"))
        #expect(scene.entities.isEmpty)
    }

    @Test("A fillet that doesn't fit is reported back to the assistant")
    func impossibleFillet() async throws {
        let scene = SceneManager()
        let tool = CreateSolidTool(sceneManager: scene)

        let result = try await tool.execute(arguments: [
            "width": .number(0.1), "height": .number(0.1), "depth": .number(0.1),
            "fillet_radius": .number(0.08),
        ])

        #expect(!result.success)
        #expect(result.message.contains("fillet"))
        #expect(scene.entities.isEmpty)
    }

    @Test("Non-positive dimensions are reported back to the assistant")
    func negativeWidth() async throws {
        let scene = SceneManager()
        let tool = CreateSolidTool(sceneManager: scene)

        let result = try await tool.execute(arguments: [
            "width": .number(-1), "height": .number(0.1), "depth": .number(0.1),
        ])

        #expect(!result.success)
        #expect(result.message.contains("greater than 0"))
    }

    @Test("A non-numeric fillet radius is reported instead of silently ignored")
    func nonNumericFillet() async throws {
        let scene = SceneManager()
        let tool = CreateSolidTool(sceneManager: scene)

        let result = try await tool.execute(arguments: [
            "width": .number(0.4), "height": .number(0.2), "depth": .number(0.1),
            "fillet_radius": .string("0.02"),
        ])

        #expect(!result.success)
        #expect(result.message.contains("fillet_radius"))
        #expect(scene.entities.isEmpty)
    }
}
