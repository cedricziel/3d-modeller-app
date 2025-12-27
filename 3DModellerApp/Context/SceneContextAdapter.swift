import Foundation
import SwiftUIAssistant

/// Adapter that provides scene context to the assistant
@MainActor
struct SceneContextAdapter: AssistantContext, @unchecked Sendable {
    let sceneManager: SceneManager

    nonisolated var contextDescription: String {
        // Return a simple description that doesn't require MainActor access
        "3D Modeling Scene"
    }

    nonisolated func serialize() -> [String: Any] {
        // Return empty context for now - the actual context is provided via system prompt
        // This avoids MainActor isolation issues
        [:]
    }
}
