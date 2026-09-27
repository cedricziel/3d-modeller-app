import CADAssistantTools
import CADModel
import CADModelKernel
import CADModelSolvers
import Foundation

extension CADSession {
    /// The session a window uses: the Open CASCADE kernel, the PlaneGCS sketch solver and the OndselSolver
    /// assembly solver.
    static func forApp(document: CADDocument) -> CADSession {
        CADSession(
            document: document, kernel: OCCTGeometryKernel(), sketchSolver: PlaneGCSSketchSolver(),
            assemblySolver: OndselAssemblySolver())
    }
}

extension CADSession {
    /// Where the assistant's export tool writes: a folder in Downloads, which the sandbox lets the app write to.
    static var assistantExportDirectory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
            .appending(path: "3D Modeller Exports")
    }
}

extension CADModelDocument {
    /// Routes the session's edits through `edit`, so each assistant tool call is one named step on the window's
    /// undo stack, shared with the menus. Every other change reaches the session at once, so a tool call never
    /// starts from a document the user has already changed; the caller still runs `session.load` to rebuild.
    @MainActor
    func connect(_ session: CADSession, undoManager: UndoManager?) {
        session.onCommit = { [weak self] model, actionName in
            self?.edit(actionName, undoManager: undoManager) { $0 = model }
        }
        onChange = { [weak session] model in session?.adopt(model) }
    }
}
