import SwiftUI

/// A scrolling list of messages
public struct MessageListView: View {
    let messages: [Message]
    let theme: any AssistantTheme
    let isProcessing: Bool

    public init(
        messages: [Message],
        theme: any AssistantTheme = DefaultAssistantTheme(),
        isProcessing: Bool = false
    ) {
        self.messages = messages
        self.theme = theme
        self.isProcessing = isProcessing
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubbleView(message: message, theme: theme)
                            .id(message.id)
                    }

                    if isProcessing {
                        TypingIndicatorView(theme: theme)
                            .id("typing-indicator")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isProcessing) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if isProcessing {
                proxy.scrollTo("typing-indicator", anchor: .bottom)
            } else if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Typing Indicator

public struct TypingIndicatorView: View {
    let theme: any AssistantTheme

    @State private var dotIndex = 0

    public init(theme: any AssistantTheme = DefaultAssistantTheme()) {
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(theme.accentColor.opacity(dotIndex == index ? 1 : 0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.assistantMessageBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.bubbleCornerRadius))
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            withAnimation(.easeInOut(duration: 0.2)) {
                dotIndex = (dotIndex + 1) % 3
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MessageListView(
        messages: [
            Message(role: .user, content: "Hello!"),
            Message(role: .assistant, content: "Hi there! How can I help you today?"),
            Message(role: .user, content: "Create a cube"),
            Message(role: .assistant, content: "I'll create a cube for you.", toolCalls: [
                ToolCall(id: "1", name: "create_primitive", arguments: [:], status: .completed)
            ])
        ],
        isProcessing: true
    )
    .frame(width: 400, height: 600)
}
