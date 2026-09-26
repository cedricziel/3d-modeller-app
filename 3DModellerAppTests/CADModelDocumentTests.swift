import CADModel
import Combine
import Foundation
import UniformTypeIdentifiers
import Testing
@testable import _D_Modeller

@Suite("CAD model document")
@MainActor
struct CADModelDocumentTests {
    private func undoManager() -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }

    private let sphere = Feature(name: "Ball", kind: .primitive(PrimitiveFeature(.sphere(radius: 5))))

    @Test("A new document is empty with one part and reads/writes the cadmodel type")
    func newDocument() {
        let document = CADModelDocument()
        #expect(document.model.parts.map(\.name) == ["Part1"])
        #expect(document.model.parts[0].features.isEmpty)
        #expect(document.model.parameters.isEmpty)
        #expect(CADModelDocument.readableContentTypes == [.cadModel])
        #expect(UTType.cadModel.identifier == "com.example.3dmodeller.cadmodel")
        #expect(UTType.cadModel.preferredFilenameExtension == "cadmodel")
    }

    @Test("Edits register a named undo step that restores the previous value, and redo reapplies it")
    func undoRedo() {
        let undoManager = undoManager()
        let document = CADModelDocument()
        let sphere = sphere
        document.edit("Add Ball", undoManager: undoManager) { $0.parts[0].features.append(sphere) }
        #expect(document.model.parts[0].features == [sphere])
        #expect(undoManager.undoActionName == "Add Ball")

        undoManager.undo()
        #expect(document.model.parts[0].features.isEmpty)
        #expect(undoManager.redoActionName == "Add Ball")

        undoManager.redo()
        #expect(document.model.parts[0].features == [sphere])
        #expect(undoManager.canUndo)
    }

    @Test("An edit that changes nothing registers nothing")
    func noOpEdit() {
        let undoManager = undoManager()
        let document = CADModelDocument()
        document.edit("Nothing", undoManager: undoManager) { _ in }
        #expect(!undoManager.canUndo)
    }

    @Test("Edits notify observers")
    func publishes() {
        let document = CADModelDocument()
        var notified = 0
        let subscription = document.objectWillChange.sink { notified += 1 }
        let sphere = sphere
        document.edit("Add Ball", undoManager: nil) { $0.parts[0].features.append(sphere) }
        #expect(notified == 1)
        subscription.cancel()
    }
}
