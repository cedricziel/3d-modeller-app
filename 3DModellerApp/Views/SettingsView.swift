import SwiftUI

/// Settings view for API configuration
struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            apiSettingsTab
                .tabItem {
                    Label("API", systemImage: "key")
                }

            appearanceSettingsTab
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
        }
        .frame(width: 450, height: 250)
        .padding()
    }

    // MARK: - API Settings

    private var apiSettingsTab: some View {
        Form {
            Section {
                Picker("Provider", selection: $appModel.llmProvider) {
                    Text("Claude").tag("claude")
                    Text("OpenAI").tag("openai")
                }

                SecureField("API Key", text: $appModel.llmApiKey)
                    .textFieldStyle(.roundedBorder)

                if appModel.llmApiKey.isEmpty {
                    Label("An API key is required for the assistant", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            } header: {
                Text("LLM Provider")
            } footer: {
                Text("Your API key is stored securely in app preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance Settings

    private var appearanceSettingsTab: some View {
        Form {
            Section {
                Toggle("Show Grid", isOn: .constant(true))
                Toggle("Show Axes", isOn: .constant(true))
            } header: {
                Text("Viewport")
            }

            Section {
                Toggle("Show Assistant on Launch", isOn: $appModel.showAssistant)
            } header: {
                Text("Assistant")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppModel())
}
