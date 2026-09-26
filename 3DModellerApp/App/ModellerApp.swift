import SwiftUI

@main
struct ModellerApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        DocumentGroup(newDocument: SceneDocument()) { configuration in
            ContentView(document: configuration.$document)
                .environmentObject(appModel)
        }
        .defaultSize(width: 1440, height: 860)
        .commands {
            CommandMenu("Tools") {
                Button("Select") {
                    appModel.selectedTool = .select
                }
                .keyboardShortcut("q", modifiers: [])

                Button("Move") {
                    appModel.selectedTool = .move
                }
                .keyboardShortcut("w", modifiers: [])

                Button("Rotate") {
                    appModel.selectedTool = .rotate
                }
                .keyboardShortcut("e", modifiers: [])

                Button("Scale") {
                    appModel.selectedTool = .scale
                }
                .keyboardShortcut("r", modifiers: [])
            }

            SidebarCommands()
            InspectorCommands()

            CommandGroup(after: .sidebar) {
                Button("Toggle Assistant") {
                    appModel.toggleAssistant()
                }
                .keyboardShortcut("\\", modifiers: .command)

                Divider()

                Button("Frame Selection") {
                    appModel.frameSelection()
                }
                .keyboardShortcut("f", modifiers: [])

                Button("Frame All") {
                    appModel.frameAll()
                }
                .keyboardShortcut("a", modifiers: .option)
            }
        }

        #if os(macOS)
            Settings {
                SettingsView()
                    .environmentObject(appModel)
            }
        #endif
    }
}
