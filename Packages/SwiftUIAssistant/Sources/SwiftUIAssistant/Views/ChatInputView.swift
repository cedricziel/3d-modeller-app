import SwiftUI

/// Text input field for sending messages
public struct ChatInputView: View {
    @Binding var text: String
    let isProcessing: Bool
    let placeholder: String
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        isProcessing: Bool = false,
        placeholder: String = "Type a message...",
        onSend: @escaping () -> Void
    ) {
        self._text = text
        self.isProcessing = isProcessing
        self.placeholder = placeholder
        self.onSend = onSend
    }

    public var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .onSubmit {
                    if !text.isEmpty && !isProcessing {
                        sendMessage()
                    }
                }
                .disabled(isProcessing)

            Button(action: sendMessage) {
                Image(systemName: isProcessing ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }

    private func sendMessage() {
        guard canSend else { return }
        onSend()
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ChatInputView(
            text: .constant("Hello!"),
            isProcessing: false,
            onSend: {}
        )

        ChatInputView(
            text: .constant(""),
            isProcessing: true,
            onSend: {}
        )
    }
    .frame(width: 400)
}
