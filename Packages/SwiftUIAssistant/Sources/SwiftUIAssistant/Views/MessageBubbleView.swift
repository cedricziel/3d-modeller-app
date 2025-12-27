import SwiftUI

/// A single message bubble in the chat
public struct MessageBubbleView: View {
    let message: Message
    let theme: any AssistantTheme

    public init(message: Message, theme: any AssistantTheme = DefaultAssistantTheme()) {
        self.message = message
        self.theme = theme
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.content)
                    .font(theme.messageFont)
                    .foregroundStyle(textColor)
                    .textSelection(.enabled)
                    .padding(theme.bubblePadding)
                    .background(backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: theme.bubbleCornerRadius))

                // Tool calls indicator
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ToolCallsIndicatorView(toolCalls: toolCalls, theme: theme)
                }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(theme.timestampFont)
                    .foregroundStyle(.secondary)
            }

            if message.role == .assistant || message.role == .system {
                Spacer(minLength: 60)
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return theme.userMessageBackground
        case .assistant, .system:
            return theme.assistantMessageBackground
        case .toolResult:
            return theme.toolExecutionColor.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user:
            return theme.userMessageTextColor
        case .assistant, .system, .toolResult:
            return theme.assistantMessageTextColor
        }
    }
}

// MARK: - Tool Calls Indicator

struct ToolCallsIndicatorView: View {
    let toolCalls: [ToolCall]
    let theme: any AssistantTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(toolCalls, id: \.id) { toolCall in
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: toolCall.status))
                        .foregroundStyle(iconColor(for: toolCall.status))
                        .font(.caption)

                    Text(toolCall.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if toolCall.status == .executing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.toolExecutionColor.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }

    private func iconName(for status: ToolCall.Status) -> String {
        switch status {
        case .pending:
            return "clock"
        case .executing:
            return "gearshape"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func iconColor(for status: ToolCall.Status) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .executing:
            return theme.toolExecutionColor
        case .completed:
            return .green
        case .failed:
            return theme.errorColor
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        MessageBubbleView(
            message: Message(role: .user, content: "Create a red cube"),
            theme: DefaultAssistantTheme()
        )

        MessageBubbleView(
            message: Message(
                role: .assistant,
                content: "I'll create a red cube for you.",
                toolCalls: [
                    ToolCall(id: "1", name: "create_primitive", arguments: [:], status: .completed)
                ]
            ),
            theme: DefaultAssistantTheme()
        )
    }
    .padding()
    .frame(width: 400)
}
