import CADAssistantTools
import CADModel
import CADModelKernel
import Foundation
import Testing

@testable import _D_Modeller

@Suite("Assistant editing")
@MainActor
struct AssistantEditingTests {
    private func undoManager() -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }

    @Test("Each tool call is one undo step named after its action, and undo reaches the session")
    func toolEditsAreUndoable() async throws {
        let undoManager = undoManager()
        let document = CADModelDocument()
        let session = CADSession(document: document.model, kernel: OCCTGeometryKernel())
        document.connect(session, undoManager: undoManager)

        let added = try await AddFeatureTool(session: session).execute(arguments: [
            "type": "box", "width": 10, "depth": 10, "height": 10,
        ])
        let parameter = try await SetParameterTool(session: session).execute(arguments: ["name": "t", "expression": 2])

        #expect(added.success && parameter.success)
        #expect(document.model == session.document)
        #expect(undoManager.undoActionName == "Add Parameter t")

        undoManager.undo()
        #expect(undoManager.undoActionName == "Add Box1")
        undoManager.undo()
        #expect(document.model.parts[0].features.isEmpty)
        #expect(!undoManager.canUndo)

        await session.load(document.model)
        #expect(session.document == document.model)
        #expect(session.result?.bodies.isEmpty == true)
        #expect(session.currentListing().contains("(no features)"))
    }

    @Test("A refused tool call adds no undo step")
    func refusalAddsNoUndo() async throws {
        let undoManager = undoManager()
        let document = CADModelDocument()
        let session = CADSession(document: document.model, kernel: OCCTGeometryKernel())
        document.connect(session, undoManager: undoManager)

        let result = try await AddFeatureTool(session: session).execute(arguments: ["type": "box", "width": 10])

        #expect(!result.success)
        #expect(!undoManager.canUndo)
        #expect(document.model == session.document)
        #expect(document.model.parts[0].features.isEmpty)
    }

    @Test("A UI edit made just before a tool call is kept, since the session adopts it at once")
    func uiEditBeforeToolCallIsKept() async throws {
        let undoManager = undoManager()
        let document = CADModelDocument()
        let session = CADSession(document: document.model, kernel: OCCTGeometryKernel())
        document.connect(session, undoManager: undoManager)
        let ball = Feature(name: "Ball", kind: .primitive(PrimitiveFeature(.sphere(radius: 5))))

        document.edit("Add Ball", undoManager: undoManager) { $0.parts[0].features.append(ball) }
        let result = try await SetParameterTool(session: session).execute(arguments: ["name": "t", "expression": 2])

        #expect(result.success)
        #expect(document.model.parts[0].features == [ball])
        #expect(document.model.parameters.map(\.name) == ["t"])
        #expect(session.document == document.model)

        undoManager.undo()
        #expect(session.document == document.model)
        #expect(session.document.parameters.isEmpty)
    }

    @Test("The app's session solves sketches, so an extruded sketch becomes a body")
    func appSessionSolvesSketches() async throws {
        let session = CADSession.forApp(document: CADDocument())
        let sketch = try await AddSketchTool(session: session).execute(arguments: [
            "plane": "XY",
            "entities": [["type": "circle", "center": [0, 0], "radius": 5]],
            "constraints": [
                ["type": "fixed", "points": ["circle1.center"], "at": [0, 0]],
                ["type": "radius", "entities": ["circle1"], "value": 5],
            ],
        ])
        #expect(sketch.message.contains("fully constrained"), "\(sketch.message)")
        let extrude = try await AddFeatureTool(session: session).execute(arguments: [
            "type": "extrude", "sketch": "Sketch1", "distance": 2,
        ])
        #expect(extrude.success)
        let volume = try #require(session.result?.bodies.first?.metrics?.volume)
        #expect(abs(volume - Double.pi * 50) < 1e-6)
    }
}
