@testable import SwiftUIAssistant

/// Streams scripted events and holds at each gate until the test releases it
actor GatedStreamingProvider: LLMProvider {
    enum Step: Sendable {
        case event(LLMStreamEvent)
        case gate
    }

    private let steps: [Step]
    private let response: LLMResponse
    private let failure: AssistantError?
    private var releasedGates = 0
    private var waiting: CheckedContinuation<Void, Never>?

    init(_ steps: [Step], response: LLMResponse, failure: AssistantError? = nil) {
        self.steps = steps
        self.response = response
        self.failure = failure
    }

    func release() {
        if let waiting {
            self.waiting = nil
            waiting.resume()
        } else {
            releasedGates += 1
        }
    }

    func sendMessage(
        _ message: String, systemPrompt: String, conversationHistory: [Message], tools: [any AssistantTool]
    ) async throws -> LLMResponse {
        response
    }

    func streamMessage(
        _ message: String,
        systemPrompt: String,
        conversationHistory: [Message],
        tools: [any AssistantTool],
        onEvent: @escaping @Sendable (LLMStreamEvent) async -> Void
    ) async throws -> LLMResponse {
        for step in steps {
            switch step {
            case .event(let event):
                await onEvent(event)
            case .gate:
                if releasedGates > 0 {
                    releasedGates -= 1
                } else {
                    await withCheckedContinuation { waiting = $0 }
                }
            }
        }
        if let failure { throw failure }
        return response
    }
}
