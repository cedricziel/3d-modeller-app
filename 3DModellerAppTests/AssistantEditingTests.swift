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
}
