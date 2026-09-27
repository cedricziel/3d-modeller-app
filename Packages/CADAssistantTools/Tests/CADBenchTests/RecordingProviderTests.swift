import SwiftUIAssistant
import Synchronization
import Testing

@testable import CADBench

@Suite("Recording provider")
struct RecordingProviderTests {
    private func send(_ provider: RecordingProvider) async throws -> LLMResponse {
        try await provider.sendMessage("hi", systemPrompt: "s", conversationHistory: [], tools: [])
    }

    @Test("Usage and the last stop reason add up over requests")
    func sumsUsage() async throws {
        let provider = RecordingProvider(
            ScriptedProvider([reply("a", input: 100, output: 20), reply("b", input: 150, output: 10)]))
        _ = try await send(provider)
        _ = try await send(provider)
        #expect(
            await provider.usage
                == Usage(requests: 2, inputTokens: 250, outputTokens: 30, retries: 0, lastStopReason: "end_turn"))
    }

    @Test("Rate limits and server errors are retried; other errors are not")
    func retries() async throws {
        let base = ScriptedProvider([
            .fail(.rateLimited(retryAfter: nil)), .fail(.providerError("HTTP 529: overloaded")), reply("ok"),
        ])
        let provider = RecordingProvider(base, retryDelays: [.zero, .zero])
        #expect(try await send(provider).content == "ok")
        #expect(await provider.usage.retries == 2)

        let failing = RecordingProvider(
            ScriptedProvider([.fail(.authenticationFailed("Invalid API key"))]), retryDelays: [.zero])
        await #expect(throws: AssistantError.self) { try await send(failing) }
        #expect(await failing.usage.retries == 0)

        let exhausted = RecordingProvider(
            ScriptedProvider([.fail(.rateLimited(retryAfter: nil)), .fail(.rateLimited(retryAfter: nil))]),
            retryDelays: [.zero])
        await #expect(throws: AssistantError.self) { try await send(exhausted) }
    }

    @Test("A turn that fails after part of it was streamed is not retried, and the events pass through")
    func noRetryAfterStreaming() async throws {
        let provider = RecordingProvider(
            ScriptedProvider([.partial("Work", then: .rateLimited(retryAfter: nil)), reply("ok")]),
            retryDelays: [.zero])
        let events = Mutex<[LLMStreamEvent]>([])

        await #expect(throws: AssistantError.self) {
            try await provider.streamMessage("hi", systemPrompt: "s", conversationHistory: [], tools: []) { event in
                events.withLock { $0.append(event) }
            }
        }

        #expect(events.withLock { $0 } == [.text("Work")])
        #expect(await provider.usage.retries == 0)
    }

    @Test("Cost uses the model's price per million tokens and is unknown for unlisted models")
    func pricing() {
        #expect(Pricing.cost(model: "claude-opus-5-5", inputTokens: 1_000_000, outputTokens: 100_000) == 6)
        #expect(Pricing.cost(model: "claude-sonnet-5", inputTokens: 500_000, outputTokens: 0) == 1)
        #expect(Pricing.cost(model: "some-model", inputTokens: 1, outputTokens: 1) == nil)
    }
}
