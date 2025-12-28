import SwiftUI

/// Protocol for customizing the appearance of the assistant views
public protocol AssistantTheme: Sendable {
    /// Background color for the chat view
    var backgroundColor: Color { get }

    /// Background color for user message bubbles
    var userMessageBackground: Color { get }

    /// Background color for assistant message bubbles
    var assistantMessageBackground: Color { get }

    /// Text color for user messages
    var userMessageTextColor: Color { get }

    /// Text color for assistant messages
    var assistantMessageTextColor: Color { get }

    /// Accent color for interactive elements
    var accentColor: Color { get }

    /// Color for tool execution indicators
    var toolExecutionColor: Color { get }

    /// Color for error states
    var errorColor: Color { get }

    /// Font for message text
    var messageFont: Font { get }

    /// Font for timestamps
    var timestampFont: Font { get }

    /// Corner radius for message bubbles
    var bubbleCornerRadius: CGFloat { get }

    /// Padding inside message bubbles
    var bubblePadding: EdgeInsets { get }
}

// MARK: - Default Theme

/// The default theme for the assistant
public struct DefaultAssistantTheme: AssistantTheme {
    public init() {}

    public var backgroundColor: Color {
        Color(.windowBackgroundColor)
    }

    public var userMessageBackground: Color {
        Color.accentColor
    }

    public var assistantMessageBackground: Color {
        Color(.unemphasizedSelectedContentBackgroundColor)
    }

    public var userMessageTextColor: Color {
        .white
    }

    public var assistantMessageTextColor: Color {
        .primary
    }

    public var accentColor: Color {
        .accentColor
    }

    public var toolExecutionColor: Color {
        .orange
    }

    public var errorColor: Color {
        .red
    }

    public var messageFont: Font {
        .body
    }

    public var timestampFont: Font {
        .caption2
    }

    public var bubbleCornerRadius: CGFloat {
        12
    }

    public var bubblePadding: EdgeInsets {
        EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    }
}

// MARK: - Theme Extension

public extension AssistantTheme where Self == DefaultAssistantTheme {
    static var `default`: DefaultAssistantTheme {
        DefaultAssistantTheme()
    }
}
