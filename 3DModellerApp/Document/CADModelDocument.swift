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

    /// Called on every change, including undo and redo, before observers re-render.
    @MainActor var onChange: ((CADDocument) -> Void)?

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

    /// The key and result of the last coalescing edit, while it is still the latest change.
    @MainActor private var coalesced: (key: String, model: CADDocument)?

    /// Records the change as an undo step. Edits with the same `coalescing` key that follow each other directly,
    /// such as the ticks of a colour picker drag, share one undo step.
    @MainActor
    func edit(
        _ actionName: String, coalescing key: String? = nil, undoManager: UndoManager?,
        _ change: (inout CADDocument) -> Void
    ) {
        var updated = model
        change(&updated)
        guard updated != model else { return }
        if let key, let coalesced, coalesced.key == key, coalesced.model == model,
            undoManager?.undoActionName == actionName
        {
            objectWillChange.send()
            storage.withLock { $0 = updated }
            onChange?(updated)
        } else {
            replace(with: updated, actionName: actionName, undoManager: undoManager)
        }
        coalesced = key.map { ($0, updated) }
    }

    @MainActor
    private func replace(with new: CADDocument, actionName: String, undoManager: UndoManager?) {
        let old = model
        guard new != old else { return }
        objectWillChange.send()
        storage.withLock { $0 = new }
        onChange?(new)
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
