import SwiftUI
import SwiftUIAssistant
import SwiftUIAssistantTools

/// Main content view with 3D viewport and assistant panel
@MainActor
struct ContentView: View {
    @Binding var document: SceneDocument
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var sceneManager = SceneManager()

    // Assistant setup
    @State private var assistant: Assistant?

    var body: some View {
        NavigationSplitView {
            SceneOutlineView(sceneManager: sceneManager)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            Viewport3DView(sceneManager: sceneManager)
                .overlay(alignment: .bottom) {
                    SceneStatisticsView(statistics: sceneManager.statistics)
                        .padding()
                }
        }
        .inspector(isPresented: $appModel.showInspector) {
            InspectorView(sceneManager: sceneManager, assistant: assistant)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 500)
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle(document.sceneData.metadata.name)
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
            syncDocumentToScene()
        }
        .onChange(of: sceneManager.revision) { _, _ in
            syncSceneToDocument()
        }
    }

    // MARK: - Assistant Setup

    private func setupAssistant() {
        guard !appModel.llmApiKey.isEmpty else { return }

        let provider = ClaudeProvider(apiKey: appModel.llmApiKey)

        let tools: [any AssistantTool] = [
            CreatePrimitiveTool(sceneManager: sceneManager),
            CreateSolidTool(sceneManager: sceneManager),
            TransformEntityTool(sceneManager: sceneManager),
            DeleteEntityTool(sceneManager: sceneManager),
            SetMaterialTool(sceneManager: sceneManager),
            DuplicateEntityTool(sceneManager: sceneManager),
            QuerySceneTool(sceneManager: sceneManager),
            FetchTool(),
            CalculatorTool(),
            TimeTool(),
        ]

        let contextProvider: @Sendable () -> any AssistantContext = { [sceneManager] in
            SceneContextAdapter(sceneManager: sceneManager)
        }

        let systemPrompt = """
            You are a 3D modeling assistant with full control over the scene.
            You can autonomously create, modify, and delete 3D objects.

            ## Your Capabilities
            - Create primitives: box, sphere, cylinder, cone, plane, torus
            - Transform objects: move, rotate, scale
            - Modify materials: color, metallic, roughness
            - Query scene state
            - Duplicate and delete entities
            - Fetch data from URLs (GET, POST, PUT, PATCH, DELETE)
            - Perform calculations (arithmetic, trigonometry, logarithms)
            - Work with dates and times (parse, format, calculate differences)

            ## Guidelines
            1. Execute operations directly - you have full scene access
            2. Provide brief explanations of what you did
            3. Use metric units (meters)
            4. When ambiguous, ask for clarification

            ## Current Context
            {context}
            """

        assistant = Assistant(
            provider: provider,
            tools: tools,
            contextProvider: contextProvider,
            configuration: AssistantConfiguration(
                systemPromptTemplate: systemPrompt
            )
        )
    }

    // MARK: - Document Sync

    private func syncDocumentToScene() {
        sceneManager.loadSceneData(document.sceneData)
    }

    private func syncSceneToDocument() {
        document.sceneData = sceneManager.toSceneData()
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
    @ObservedObject var sceneManager: SceneManager
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
                PropertiesInspectorView(sceneManager: sceneManager)
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

// MARK: - Scene Statistics View

struct SceneStatisticsView: View {
    let statistics: SceneStatistics

    var body: some View {
        HStack(spacing: 16) {
            Label("\(statistics.entityCount) objects", systemImage: "cube")
            Label("\(statistics.triangleCount) triangles", systemImage: "triangle")
            Label("\(statistics.materialCount) materials", systemImage: "paintpalette")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}

#Preview {
    ContentView(document: .constant(SceneDocument()))
        .environmentObject(AppModel())
}
