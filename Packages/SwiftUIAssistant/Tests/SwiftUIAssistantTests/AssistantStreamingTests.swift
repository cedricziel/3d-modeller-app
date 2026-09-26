import Foundation
import Testing

@testable import SwiftUIAssistant

@Suite("Assistant streaming")
@MainActor
struct AssistantStreamingTests {
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test("Partial text is published before the turn completes")
    func partialTextBeforeCompletion() async throws {
        let provider = GatedStreamingProvider(
            [.event(.text("Hel")), .event(.text("lo")), .gate],
            response: LLMResponse(content: "Hello", toolCalls: nil, stopReason: .endTurn))
        let assistant = Assistant(provider: provider, tools: [], contextProvider: { MockContext() })

        let task = Task { try await assistant.send("hi") }
        let streamed = await waitUntil { assistant.streamingReply?.text == "Hello" }
        let messagesWhileStreaming = assistant.messages.count
        await provider.release()
        try await task.value

        #expect(streamed)
        #expect(messagesWhileStreaming == 1)
        #expect(assistant.streamingReply == nil)
        #expect(assistant.messages.last?.content == "Hello")
    }

    @Test("Thinking shows until the first text arrives")
    func thinkingState() async throws {
        let provider = GatedStreamingProvider(
            [.event(.thinking("")), .gate, .event(.text("Done")), .gate],
            response: LLMResponse(content: "Done", toolCalls: nil, stopReason: .endTurn))
        let assistant = Assistant(provider: provider, tools: [], contextProvider: { MockContext() })

        let task = Task { try await assistant.send("hi") }
        let thinking = await waitUntil { assistant.streamingReply?.isThinking == true }
        await provider.release()
        let answering = await waitUntil { assistant.streamingReply?.text == "Done" }
        let stillThinking = assistant.streamingReply?.isThinking
        await provider.release()
        try await task.value

        #expect(thinking)
        #expect(answering)
        #expect(stillThinking == false)
    }

    @Test("The partial reply is dropped when the turn fails")
    func failedTurnClearsReply() async throws {
        let provider = GatedStreamingProvider(
            [.event(.text("Half"))], response: LLMResponse(content: nil, toolCalls: nil, stopReason: .endTurn),
            failure: .networkError("dropped"))
        let assistant = Assistant(provider: provider, tools: [], contextProvider: { MockContext() })

        await #expect(throws: AssistantError.self) { try await assistant.send("hi") }

        #expect(assistant.streamingReply == nil)
    }

    @Test("The list shows a thinking indicator while thinking and dots otherwise")
    func activityIndicator() {
        #expect(MessageListView.indicator(isProcessing: false, reply: nil) == .none)
        #expect(MessageListView.indicator(isProcessing: true, reply: nil) == .typing)
        #expect(MessageListView.indicator(isProcessing: true, reply: StreamingReply(isThinking: true)) == .thinking)
        #expect(MessageListView.indicator(isProcessing: true, reply: StreamingReply(text: "Hi")) == .typing)
    }
}
