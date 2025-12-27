import SwiftUI

/// View for displaying tool execution status and results
public struct ToolExecutionView: View {
    let toolCall: ToolCall
    let theme: any AssistantTheme

    public init(toolCall: ToolCall, theme: any AssistantTheme = DefaultAssistantTheme()) {
        self.toolCall = toolCall
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Status icon
            statusIcon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                // Tool name
                Text(toolCall.name)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)

                // Result message
                if let result = toolCall.result {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(result.success ? .secondary : theme.errorColor)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Status badge
            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch toolCall.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .executing:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(theme.errorColor)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(statusText)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusBadgeColor.opacity(0.2))
            .foregroundStyle(statusBadgeColor)
            .clipShape(Capsule())
    }

    private var statusText: String {
        switch toolCall.status {
        case .pending:
            return "Pending"
        case .executing:
            return "Running"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        }
    }

    private var statusBadgeColor: Color {
        switch toolCall.status {
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

    private var backgroundColor: Color {
        theme.assistantMessageBackground.opacity(0.5)
    }

    private var borderColor: Color {
        switch toolCall.status {
        case .pending:
            return .secondary.opacity(0.3)
        case .executing:
            return theme.toolExecutionColor.opacity(0.5)
        case .completed:
            return .green.opacity(0.3)
        case .failed:
            return theme.errorColor.opacity(0.3)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        ToolExecutionView(
            toolCall: ToolCall(id: "1", name: "create_primitive", arguments: [:], status: .pending),
            theme: DefaultAssistantTheme()
        )

        ToolExecutionView(
            toolCall: ToolCall(id: "2", name: "create_primitive", arguments: [:], status: .executing),
            theme: DefaultAssistantTheme()
        )

        ToolExecutionView(
            toolCall: ToolCall(
                id: "3",
                name: "create_primitive",
                arguments: [:],
                status: .completed,
                result: ToolExecutionResult(success: true, message: "Created cube 'Cube_1'", data: nil)
            ),
            theme: DefaultAssistantTheme()
        )

        ToolExecutionView(
            toolCall: ToolCall(
                id: "4",
                name: "delete_entity",
                arguments: [:],
                status: .failed,
                result: ToolExecutionResult(success: false, message: "Entity not found", data: nil)
            ),
            theme: DefaultAssistantTheme()
        )
    }
    .padding()
    .frame(width: 350)
}
