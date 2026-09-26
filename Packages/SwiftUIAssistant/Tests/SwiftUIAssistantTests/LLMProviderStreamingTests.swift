import Foundation
import Synchronization
import Testing

@testable import SwiftUIAssistant

@Suite("LLMProvider streaming")
struct LLMProviderStreamingTests {
    @Test("A provider that only answers whole turns streams its response without events")
    func defaultStreamingPath() async throws {
        let provider = MockLLMProvider()
        await provider.queueTextResponse("Hello")
        let events = Mutex<[LLMStreamEvent]>([])

        let response = try await provider.streamMessage(
            "hi", systemPrompt: "s", conversationHistory: [.user("hi")], tools: []
        ) { event in events.withLock { $0.append(event) } }

        #expect(response.content == "Hello")
        #expect(events.withLock { $0 }.isEmpty)
    }
}
