import SwiftUI

/// A collapsible panel containing the assistant chat
///
/// This is designed to be used as a trailing sidebar in your app layout.
///
/// ```swift
/// HSplitView {
///     MainContentView()
///     AssistantPanel(assistant: assistant, isPresented: $showAssistant)
/// }
/// ```
public struct AssistantPanel: View {
    @ObservedObject var assistant: Assistant
    @Binding var isPresented: Bool
    let theme: any AssistantTheme
    let minWidth: CGFloat
    let idealWidth: CGFloat
    let maxWidth: CGFloat

    public init(
        assistant: Assistant,
        isPresented: Binding<Bool>,
        theme: any AssistantTheme = DefaultAssistantTheme(),
        minWidth: CGFloat = 280,
        idealWidth: CGFloat = 350,
        maxWidth: CGFloat = 500
    ) {
        self.assistant = assistant
        self._isPresented = isPresented
        self.theme = theme
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
    }

    public var body: some View {
        if isPresented {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Assistant")
                        .font(.headline)

                    Spacer()

                    Button {
                        assistant.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear conversation")
                    .disabled(assistant.messages.isEmpty)

                    Button {
                        withAnimation {
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Close assistant")
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.regularMaterial)

                Divider()

                // Chat
                AssistantView(assistant: assistant, theme: theme)
            }
            .frame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth)
        }
    }
}

// MARK: - Preview

#Preview {
    Text("Main Content")
        .frame(width: 600, height: 400)
}
