import SwiftUI

/// Opens the focused window's export sheet.
struct ExportAction {
    let perform: () -> Void
}

extension FocusedValues {
    @Entry var exportAction: ExportAction?
}

struct ExportCommands: Commands {
    @FocusedValue(\.exportAction) private var exportAction

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export…") { exportAction?.perform() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(exportAction == nil)
        }
    }
}
