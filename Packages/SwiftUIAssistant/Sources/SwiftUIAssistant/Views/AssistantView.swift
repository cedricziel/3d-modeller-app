import SwiftUI

/// The main assistant chat view
///
/// This is a drop-in component that provides a complete chat interface
/// for interacting with the assistant.
///
/// ```swift
/// AssistantView(assistant: assistant)
/// ```
public struct AssistantView: View {
    @ObservedObject var assistant: Assistant
    let theme: any AssistantTheme

    @State private var inputText = ""

    public init(
        assistant: Assistant,
        theme: any AssistantTheme = DefaultAssistantTheme()
    ) {
        self.assistant = assistant
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Messages
            MessageListView(
                messages: assistant.messages,
                theme: theme,
                isProcessing: assistant.isProcessing
            )

            Divider()

            // Input
            ChatInputView(
                text: $inputText,
                isProcessing: assistant.isProcessing,
                onSend: sendMessage
            )
        }
        .background(theme.backgroundColor)
    }

    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        inputText = ""

        Task {
            do {
                try await assistant.send(message)
            } catch {
                // Error is stored in assistant.currentError
                print("Assistant error: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    // Note: Preview requires a mock assistant setup
    Text("AssistantView Preview")
        .frame(width: 400, height: 600)
}
