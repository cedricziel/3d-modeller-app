import SwiftUI
import Combine

/// Global application state
@MainActor
final class AppModel: ObservableObject {
    // MARK: - UI State

    /// Whether the assistant panel is visible
    @Published var showAssistant: Bool = true

    /// Currently selected tool
    @Published var selectedTool: EditingTool = .select

    /// API key for the LLM provider
    @AppStorage("llmApiKey") var llmApiKey: String = ""

    /// Selected LLM provider
    @AppStorage("llmProvider") var llmProvider: String = "claude"

    // MARK: - Editing Tools

    enum EditingTool: String, CaseIterable, Identifiable {
        case select
        case move
        case rotate
        case scale

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .select: return "arrow.up.left.and.arrow.down.right"
            case .move: return "arrow.up.and.down.and.arrow.left.and.right"
            case .rotate: return "arrow.triangle.2.circlepath"
            case .scale: return "arrow.up.left.and.arrow.down.right.circle"
            }
        }

        var label: String {
            switch self {
            case .select: return "Select"
            case .move: return "Move"
            case .rotate: return "Rotate"
            case .scale: return "Scale"
            }
        }

        var shortcut: String {
            switch self {
            case .select: return "Q"
            case .move: return "W"
            case .rotate: return "E"
            case .scale: return "R"
            }
        }
    }

    // MARK: - View Actions

    func frameSelection() {
        // Will be implemented with scene manager
        print("Frame selection")
    }

    func frameAll() {
        // Will be implemented with scene manager
        print("Frame all")
    }
}
