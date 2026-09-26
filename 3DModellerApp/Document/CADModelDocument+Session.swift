import CADAssistantTools
import Foundation

extension CADModelDocument {
    /// Routes the session's edits through `edit`, so each assistant tool call is one named step on the window's
    /// undo stack, shared with the menus.
    @MainActor
    func connect(_ session: CADSession, undoManager: UndoManager?) {
        session.onCommit = { [weak self] model, actionName in
            self?.edit(actionName, undoManager: undoManager) { $0 = model }
        }
    }
}
