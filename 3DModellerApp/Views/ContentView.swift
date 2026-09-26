import CADModel
import CADModelKernel
import SwiftUI
import SwiftUIAssistant
import SwiftUIAssistantTools

@MainActor
struct ContentView: View {
    @ObservedObject var document: CADModelDocument
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var result: RebuildResult?
    @State private var selection: UUID?
    @State private var assistant: Assistant?

    private static let engine = RebuildEngine(kernel: OCCTGeometryKernel())

    var body: some View {
        NavigationSplitView {
            FeatureOutlineView(
                model: document.model,
                result: result,
                selection: $selection,
                setSuppressed: setSuppressed,
                delete: delete
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            Viewport3DView(result: result)
                .overlay(alignment: .bottom) {
                    ModelStatisticsView(result: result)
                        .padding()
                }
        }
        .inspector(isPresented: $appModel.showInspector) {
            InspectorView(
                feature: selection.flatMap(document.model.feature(id:)),
                featureResult: selection.flatMap { result?.feature(id: $0) },
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
            if let rebuilt = try? await Self.engine.rebuild(document.model) {
                result = rebuilt
            }
        }
    }

    // MARK: - Edits

    private func setSuppressed(_ feature: Feature, _ suppressed: Bool) {
        let action = suppressed ? "Suppress \(feature.name)" : "Unsuppress \(feature.name)"
        document.edit(action, undoManager: undoManager) { model in
            model.updateFeature(id: feature.id) { $0.suppressed = suppressed }
        }
    }

    private func delete(_ feature: Feature) {
        document.edit("Delete \(feature.name)", undoManager: undoManager) { model in
            model.removeFeature(id: feature.id)
        }
    }

    // MARK: - Assistant Setup

    private func setupAssistant() {
        guard !appModel.llmApiKey.isEmpty else { return }

        let systemPrompt = """
            You are the assistant of a parametric CAD app. Models are measured in millimetres.
            You cannot read or change the model yet; modelling tools arrive in a later release.
            If asked to model something, say so briefly and describe how you would build it
            from boxes, cylinders, spheres, cones and tori combined with booleans.

            You can:
            - Fetch data from URLs (GET, POST, PUT, PATCH, DELETE)
            - Perform calculations (arithmetic, trigonometry, logarithms)
            - Work with dates and times (parse, format, calculate differences)

            ## Current Context
            {context}
            """

        assistant = Assistant(
            provider: ClaudeProvider(apiKey: appModel.llmApiKey),
            tools: [FetchTool(), CalculatorTool(), TimeTool()],
            contextProvider: { EmptyContext() },
            configuration: AssistantConfiguration(systemPromptTemplate: systemPrompt)
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
