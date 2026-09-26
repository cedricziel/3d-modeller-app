import CADAssistantTools
import CADModel
import CADModelKernel
import SwiftUI
import SwiftUIAssistant

@MainActor
struct ContentView: View {
    @ObservedObject var document: CADModelDocument
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var session: CADSession
    @State private var selection: UUID?
    @State private var assistant: Assistant?
    @State private var refusal: String?

    init(document: CADModelDocument) {
        _document = ObservedObject(wrappedValue: document)
        _session = State(wrappedValue: CADSession(document: document.model, kernel: OCCTGeometryKernel()))
    }

    var body: some View {
        NavigationSplitView {
            FeatureOutlineView(
                model: document.model,
                result: session.result,
                selection: $selection,
                setSuppressed: setSuppressed,
                delete: delete
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            Viewport3DView(result: session.result)
                .overlay(alignment: .bottom) {
                    ModelStatisticsView(result: session.result)
                        .padding()
                }
        }
        .inspector(isPresented: $appModel.showInspector) {
            InspectorView(
                feature: selection.flatMap(document.model.feature(id:)),
                featureResult: selection.flatMap { session.result?.feature(id: $0) },
                assistant: assistant
            )
            .inspectorColumnWidth(min: 280, ideal: 340, max: 500)
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ToolPicker(selectedTool: $appModel.selectedTool)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appModel.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle Inspector (⌃⌘I)")
            }
        }
        .task {
            setupAssistant()
        }
        .task(id: document.model) {
            await session.load(document.model)
        }
        .onChange(of: undoManager, initial: true) { _, undoManager in
            document.connect(session, undoManager: undoManager)
        }
        .alert(
            "Can't Delete", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } }),
            presenting: refusal
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Edits

    private func setSuppressed(_ feature: Feature, _ suppressed: Bool) {
        let action = suppressed ? "Suppress \(feature.name)" : "Unsuppress \(feature.name)"
        document.edit(action, undoManager: undoManager) { model in
            model.updateFeature(id: feature.id) { $0.suppressed = suppressed }
        }
    }

    /// Goes through the session so body references are repaired, or the delete refused, as with delete_feature.
    private func delete(_ feature: Feature) {
        Task {
            refusal = await session.deleteFeature(id: feature.id)
        }
    }

    // MARK: - Assistant Setup

    private func setupAssistant() {
        guard !appModel.llmApiKey.isEmpty else { return }

        assistant = Assistant(
            provider: ClaudeProvider(apiKey: appModel.llmApiKey),
            tools: CADTools.all(session: session),
            contextProvider: { [session] in session.assistantContext() },
            configuration: CADAssistantPrompt.configuration
        )
    }
}

// MARK: - Tool Picker

@MainActor
struct ToolPicker: View {
    @Binding var selectedTool: AppModel.EditingTool

    var body: some View {
        Picker("Tool", selection: $selectedTool) {
            ForEach(AppModel.EditingTool.allCases) { tool in
                Label(tool.label, systemImage: tool.icon)
                    .help("\(tool.label) (\(tool.shortcut))")
                    .tag(tool)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
    }
}

// MARK: - Inspector

@MainActor
struct InspectorView: View {
    let feature: Feature?
    let featureResult: FeatureResult?
    let assistant: Assistant?
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Inspector", selection: $appModel.inspectorTab) {
                    ForEach(AppModel.InspectorTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if appModel.inspectorTab == .assistant, let assistant {
                    ClearConversationButton(assistant: assistant)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch appModel.inspectorTab {
            case .properties:
                FeatureInspectorView(feature: feature, result: featureResult)
            case .assistant:
                if let assistant {
                    AssistantView(assistant: assistant)
                } else {
                    AssistantNotConfiguredView()
                }
            }
        }
    }
}

@MainActor
private struct ClearConversationButton: View {
    @ObservedObject var assistant: Assistant

    var body: some View {
        Button {
            assistant.clearHistory()
        } label: {
            Label("Clear Conversation", systemImage: "trash")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help("Clear conversation")
        .disabled(assistant.messages.isEmpty)
    }
}

private struct AssistantNotConfiguredView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Assistant Not Configured")
                .font(.headline)
            Text("Add your API key in Settings to enable the AI assistant.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SettingsLink {
                Text("Open Settings")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView(document: CADModelDocument())
        .environmentObject(AppModel())
}
