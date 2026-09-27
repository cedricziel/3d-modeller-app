import SwiftUI

/// A scrolling list of messages
public struct MessageListView: View {
    let messages: [Message]
    let theme: any AssistantTheme
    let isProcessing: Bool
    let streamingReply: StreamingReply?

    public init(
        messages: [Message],
        theme: any AssistantTheme = DefaultAssistantTheme(),
        isProcessing: Bool = false,
        streamingReply: StreamingReply? = nil
    ) {
        self.messages = messages
        self.theme = theme
        self.isProcessing = isProcessing
        self.streamingReply = streamingReply
    }

    enum ActivityIndicator: Equatable {
        case none
        case typing
        case thinking
    }

    static func indicator(isProcessing: Bool, reply: StreamingReply?) -> ActivityIndicator {
        guard isProcessing else { return .none }
        return reply?.isThinking == true ? .thinking : .typing
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubbleView(message: message, theme: theme)
                            .id(message.id)
                    }

                    if let text = streamingReply?.text, !text.isEmpty {
                        MessageBubbleView(message: .assistant(text), theme: theme)
                            .id("streaming-reply")
                    }

                    switch Self.indicator(isProcessing: isProcessing, reply: streamingReply) {
                    case .none:
                        EmptyView()
                    case .typing:
                        TypingIndicatorView(theme: theme)
                            .id("activity-indicator")
                    case .thinking:
                        ThinkingIndicatorView(theme: theme)
                            .id("activity-indicator")
                    }
                }
                .padding()
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: isProcessing) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: streamingReply) { _, _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        // Defer to next run loop to avoid "Publishing changes from within view updates" warning
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    performScroll(proxy: proxy)
                }
            } else {
                performScroll(proxy: proxy)
            }
        }
    }

    private func performScroll(proxy: ScrollViewProxy) {
        if isProcessing {
            proxy.scrollTo("activity-indicator", anchor: .bottom)
        } else if let lastMessage = messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
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
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [self] _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.2)) {
                    dotIndex = (dotIndex + 1) % 3
                }
            }
        }
    }
}

// MARK: - Thinking Indicator

public struct ThinkingIndicatorView: View {
    let theme: any AssistantTheme

    public init(theme: any AssistantTheme = DefaultAssistantTheme()) {
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.assistantMessageBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.bubbleCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    MessageListView(
        messages: [
            Message(role: .user, content: "Hello!"),
            Message(role: .assistant, content: "Hi there! How can I help you today?"),
            Message(role: .user, content: "Create a cube"),
            Message(
                role: .assistant, content: "I'll create a cube for you.",
                toolCalls: [
                    ToolCall(id: "1", name: "create_primitive", arguments: [:], status: .completed)
                ]),
        ],
        isProcessing: true
    )
    .frame(width: 400, height: 600)
}
