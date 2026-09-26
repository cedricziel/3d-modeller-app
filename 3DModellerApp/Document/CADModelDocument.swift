import CADModel
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

extension UTType {
    static var cadModel: UTType { UTType(exportedAs: "com.example.3dmodeller.cadmodel") }
}

/// A reference document so SwiftUI tracks unsaved changes through the window's undo manager, where `edit` records
/// each change; a `FileDocument` binding would add an unnamed undo step of its own on every write.
final class CADModelDocument: ReferenceFileDocument {
    private let storage: Mutex<CADDocument>

    var model: CADDocument { storage.withLock { $0 } }

    static var readableContentTypes: [UTType] { [.cadModel] }

    init(model: CADDocument = CADDocument()) {
        storage = Mutex(model)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        storage = Mutex(try CADDocument(json: data))
    }

    func snapshot(contentType: UTType) throws -> CADDocument { model }

    func fileWrapper(snapshot: CADDocument, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.jsonData())
    }

    @MainActor
    func edit(_ actionName: String, undoManager: UndoManager?, _ change: (inout CADDocument) -> Void) {
        var updated = model
        change(&updated)
        replace(with: updated, actionName: actionName, undoManager: undoManager)
    }

    @MainActor
    private func replace(with new: CADDocument, actionName: String, undoManager: UndoManager?) {
        let old = model
        guard new != old else { return }
        objectWillChange.send()
        storage.withLock { $0 = new }
        guard let undoManager else { return }
        let opensGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if opensGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { document in
            document.replace(with: old, actionName: actionName, undoManager: undoManager)
        }
        undoManager.setActionName(actionName)
        if opensGroup { undoManager.endUndoGrouping() }
    }
}
