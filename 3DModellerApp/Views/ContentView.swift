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
            // Left sidebar: Scene outline
            SceneOutlineView(sceneManager: sceneManager)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } content: {
            // Center: 3D Viewport
            Viewport3DView(sceneManager: sceneManager)
                .overlay(alignment: .topLeading) {
                    ToolbarView(selectedTool: $appModel.selectedTool)
                        .padding()
                }
                .overlay(alignment: .bottom) {
                    SceneStatisticsView(statistics: sceneManager.statistics)
                        .padding()
                }
                .navigationSplitViewColumnWidth(min: 400, ideal: 700)
        } detail: {
            // Right sidebar: Properties Inspector (always visible)
            PropertiesInspectorView(sceneManager: sceneManager)
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 360)
        }
        .inspector(isPresented: $appModel.showAssistant) {
            if let assistant = assistant {
                AssistantPanel(
                    assistant: assistant,
                    isPresented: $appModel.showAssistant
                )
            } else {
                // No API key configured - show setup prompt
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
                .frame(minWidth: 300)
                .padding()
            }
        }
        .inspectorColumnWidth(min: 300, ideal: 350, max: 500)
        .frame(minWidth: 1150, minHeight: 600)
        .navigationTitle(document.sceneData.metadata.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.showAssistant.toggle()
                } label: {
                    Image(systemName: appModel.showAssistant ? "bubble.left.fill" : "bubble.left")
                }
                .help("Toggle Assistant (⌘\\)")
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

// MARK: - Toolbar View

@MainActor
struct ToolbarView: View {
    @Binding var selectedTool: AppModel.EditingTool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppModel.EditingTool.allCases) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Image(systemName: tool.icon)
                        .font(.title2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .tint(selectedTool == tool ? .accentColor : .secondary)
                .help("\(tool.label) (\(tool.shortcut))")
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
