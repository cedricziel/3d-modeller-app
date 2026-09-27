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
    @State private var driver: JointDriver
    @State private var selection: UUID?
    @State private var assistant: Assistant?
    @State private var refusal: String?
    /// The content the user chose; nil follows the document.
    @State private var chosenContent: ViewportContent?
    @State private var isExporting = false

    init(document: CADModelDocument) {
        _document = ObservedObject(wrappedValue: document)
        let session = CADSession.forApp(document: document.model)
        session.exportDirectory = CADSession.assistantExportDirectory
        _session = State(wrappedValue: session)
        _driver = State(wrappedValue: JointDriver { [session] document in try await session.preview(document) })
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
            Viewport3DView(result: driver.preview ?? session.result, content: viewportContent)
                .overlay(alignment: .top) {
                    if !document.model.instances.isEmpty {
                        Picker("Show", selection: viewportContentBinding) {
                            ForEach(ViewportContent.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .padding()
                    }
                }
                .overlay(alignment: .bottom) {
                    ModelStatisticsView(result: session.result)
                        .padding()
                }
        }
        .inspector(isPresented: $appModel.showInspector) {
            InspectorView(
                instance: selection.flatMap { id in document.model.instances.first { $0.id == id } },
                joint: selection.flatMap { id in document.model.joints.first { $0.id == id } },
                jointResult: selection.flatMap { session.result?.assembly?.joint(id: $0) },
                model: document.model,
                instanceResult: selection.flatMap { session.result?.assembly?.instance(id: $0) },
                feature: selection.flatMap(document.model.feature(id:)),
                featureResult: selection.flatMap { session.result?.feature(id: $0) },
                sketchResult: selection.flatMap { session.result?.sketch(id: $0) },
                assistant: assistant,
                driver: driver,
                moveJoint: moveJoint,
                setAppearance: setAppearance
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
        .focusedSceneValue(\.exportAction, ExportAction { isExporting = true })
        .sheet(isPresented: $isExporting) {
            ExportSheet(session: session, scopes: ExportScope.choices(for: document.model, result: session.result))
        }
        .task(id: document.model) {
            await session.load(document.model)
            driver.clear()
        }
        .onChange(of: selection) { _, selection in
            driver.clear()
            if let content = ViewportContent.following(selection: selection, in: document.model) {
                chosenContent = content
            }
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

    private var viewportContent: ViewportContent {
        guard !document.model.instances.isEmpty else { return .parts }
        return chosenContent ?? ViewportContent.automatic(for: document.model)
    }

    private var viewportContentBinding: Binding<ViewportContent> {
        Binding(get: { viewportContent }, set: { chosenContent = $0 })
    }

    // MARK: - Edits

    private func setSuppressed(_ feature: Feature, _ suppressed: Bool) {
        let action = suppressed ? "Suppress \(feature.name)" : "Unsuppress \(feature.name)"
        document.edit(action, undoManager: undoManager) { model in
            model.updateFeature(id: feature.id) { $0.suppressed = suppressed }
        }
    }

    private func moveJoint(_ joint: Joint, to value: Double) {
        document.edit("Move \(joint.name)", undoManager: undoManager) { model in
            guard let index = model.joints.firstIndex(where: { $0.id == joint.id }) else { return }
            model.assembly?.joints[index].value = .number(value)
        }
    }

    private func setAppearance(_ target: AppearanceTarget, _ appearance: Appearance?) {
        document.edit(
            "\(appearance == nil ? "Clear" : "Set") appearance of \(target.name(in: document.model))",
            undoManager: undoManager
        ) { model in
            target.apply(appearance, to: &model)
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
    let instance: Instance?
    let joint: Joint?
    let jointResult: JointResult?
    let model: CADDocument
    let instanceResult: InstanceResult?
    let feature: Feature?
    let featureResult: FeatureResult?
    let sketchResult: SketchResult?
    let assistant: Assistant?
    let driver: JointDriver
    let moveJoint: (Joint, Double) -> Void
    let setAppearance: (AppearanceTarget, Appearance?) -> Void
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
                if let instance {
                    InstanceInspectorView(
                        instance: instance, partName: model.part(id: instance.part)?.name, result: instanceResult,
                        partAppearance: model.part(id: instance.part)?.appearance,
                        setAppearance: { setAppearance(.instance(instance.id), $0) })
                } else if let joint {
                    JointInspectorView(
                        joint: joint, model: model, result: jointResult, driver: driver,
                        move: { moveJoint(joint, $0) })
                } else {
                    let part = feature.flatMap { feature in
                        model.parts.first { $0.features.contains { $0.id == feature.id } }
                    }
                    FeatureInspectorView(
                        feature: feature, result: featureResult, sketch: sketchResult, part: part,
                        setPartAppearance: part.map { part in { setAppearance(.part(part.id), $0) } })
                }
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
