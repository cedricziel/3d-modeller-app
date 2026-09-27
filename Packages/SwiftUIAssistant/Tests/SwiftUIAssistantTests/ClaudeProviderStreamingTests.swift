import Foundation
import Synchronization
import Testing

@testable import SwiftUIAssistant

@Suite("ClaudeProvider streaming")
struct ClaudeProviderStreamingTests {
    private struct Run {
        let result: Result<LLMResponse, any Error>
        let events: [LLMStreamEvent]

        var response: LLMResponse {
            get throws { try result.get() }
        }

        var error: (any Error)? {
            if case .failure(let error) = result { return error }
            return nil
        }
    }

    private func stream(
        _ scripts: [FakeSSEProtocol.Script], idleTimeout: Duration = .seconds(30)
    ) async -> Run {
        let (session, baseURL) = FakeSSEProtocol.serving(scripts)
        let provider = ClaudeProvider(apiKey: "test", baseURL: baseURL, idleTimeout: idleTimeout, session: session)
        let events = Mutex<[LLMStreamEvent]>([])
        let result: Result<LLMResponse, any Error>
        do {
            result = .success(
                try await provider.streamMessage(
                    "hi", systemPrompt: "s", conversationHistory: [.user("hi")], tools: []
                ) { event in events.withLock { $0.append(event) } })
        } catch {
            result = .failure(error)
        }
        return Run(result: result, events: events.withLock { $0 })
    }

    private func stream(_ steps: FakeSSEProtocol.Step..., idleTimeout: Duration = .seconds(30)) async -> Run {
        await stream([FakeSSEProtocol.Script(steps: steps)], idleTimeout: idleTimeout)
    }

    @Test("Requests ask for a stream and time out only when the stream goes quiet")
    func streamingRequest() async throws {
        let provider = ClaudeProvider(apiKey: "test", idleTimeout: .seconds(120))
        let request = try await provider.buildRequest(systemPrompt: "s", messages: [.user("hi")], tools: [])
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(body["stream"] as? Bool == true)
        #expect(request.timeoutInterval == 120)
    }

    @Test("A text-only turn reports each text delta and returns the whole text with usage")
    func textOnly() async throws {
        let run = await stream(.data(SSEFixtures.textOnly))
        let response = try run.response

        #expect(run.events == [.text("Hel"), .text("lo")])
        #expect(response.content == "Hello")
        #expect(response.stopReason == .endTurn)
        #expect(response.toolCalls == nil)
        #expect(response.usage?.inputTokens == 25)
        #expect(response.usage?.outputTokens == 12)
    }

    @Test("Thinking is reported before the text and kept with its signature for replay")
    func thinkingThenText() async throws {
        let run = await stream(.data(SSEFixtures.thinkingThenText))
        let response = try run.response
        let thinking = try #require(response.rawContent?.first)

        #expect(run.events == [.thinking(""), .thinking("A cube"), .text("Done.")])
        #expect(response.content == "Done.")
        #expect(thinking["type"]?.stringValue == "thinking")
        #expect(thinking["thinking"]?.stringValue == "A cube")
        #expect(thinking["signature"]?.stringValue == "sig-1")
    }

    @Test("A tool call's input is assembled from its JSON fragments")
    func splitToolUse() async throws {
        let run = await stream(.data(SSEFixtures.splitToolUse))
        let response = try run.response
        let call = try #require(response.toolCalls?.first)

        #expect(run.events.isEmpty)
        #expect(response.stopReason == .toolUse)
        #expect(call.id == "toolu_1")
        #expect(call.name == "create_primitive")
        #expect(call.arguments == ["type": "box", "size": 2])
        #expect(response.rawContent?.first?["input"] == ["type": "box", "size": 2])
    }

    @Test("Several content blocks come back in order, each tool call complete")
    func multipleBlocks() async throws {
        let run = await stream(.data(SSEFixtures.multipleBlocks))
        let response = try run.response

        #expect(response.content == "Two parts.")
        #expect(response.toolCalls?.map(\.id) == ["toolu_a", "toolu_b"])
        #expect(response.toolCalls?.last?.arguments == ["type": "sphere"])
        #expect(
            response.rawContent?.compactMap { $0["type"]?.stringValue } == ["thinking", "text", "tool_use", "tool_use"])
        #expect(response.rawContent?.first?["signature"]?.stringValue == "sig-2")
    }

    @Test("Stream fragments may split lines anywhere")
    func splitLines() async throws {
        let text = SSEFixtures.textOnly
        let cut = text.index(text.startIndex, offsetBy: text.count / 2)
        let run = await stream(.data(String(text[..<cut])), .data(String(text[cut...])))

        #expect(try run.response.content == "Hello")
    }

    @Test("A tool call cut off by the token limit is dropped and the turn ends with max_tokens")
    func truncatedToolUse() async throws {
        let run = await stream(.data(SSEFixtures.truncatedToolUse))
        let response = try run.response

        #expect(response.stopReason == .maxTokens)
        #expect(response.content == "Sketching.")
        #expect(response.toolCalls == nil)
        #expect(response.rawContent?.count == 1)
    }

    @Test("Invalid tool input in a turn that was not cut off fails the turn")
    func invalidToolInput() async throws {
        let fixture = SSEFixtures.truncatedToolUse.replacingOccurrences(of: "max_tokens", with: "tool_use")
        let run = await stream(.data(fixture))

        guard case .parsingError? = run.error as? AssistantError else {
            Issue.record("expected a parsing error, got \(String(describing: run.error))")
            return
        }
    }

    @Test("A data line that is not JSON fails the turn")
    func malformedData() async throws {
        let run = await stream(.data(SSEFixtures.messageStart + "data: {not json\n\n"))

        guard case .parsingError? = run.error as? AssistantError else {
            Issue.record("expected a parsing error, got \(String(describing: run.error))")
            return
        }
    }

    @Test("CRLF line endings and characters split across chunks are read intact")
    func crlfAndSplitCharacters() async throws {
        let fixture = Data(
            SSEFixtures.textOnly.replacingOccurrences(of: "\"Hel\"", with: "\"Hé\"")
                .replacingOccurrences(of: "\n", with: "\r\n").utf8)
        let accent = try #require(fixture.firstRange(of: Data("é".utf8)))
        let cut = accent.lowerBound + 1

        let run = await stream(.bytes(fixture[..<cut]), .bytes(fixture[cut...]))

        #expect(run.events == [.text("Hé"), .text("lo")])
        #expect(try run.response.content == "Hélo")
    }

    @Test("An error event mid-stream fails the turn after the text so far was reported")
    func errorEvent() async throws {
        let run = await stream(.data(SSEFixtures.partialText + SSEFixtures.overloadedError))

        #expect(run.events == [.text("Working")])
        guard case .providerError(let message)? = run.error as? AssistantError else {
            Issue.record("expected a provider error, got \(String(describing: run.error))")
            return
        }
        #expect(message.hasPrefix("HTTP 529"))
    }

    @Test("A dropped connection fails the turn with the network error")
    func connectionDrop() async throws {
        let run = await stream(.data(SSEFixtures.partialText), .fail(.networkConnectionLost))

        #expect((run.error as? URLError)?.code == .networkConnectionLost)
    }

    @Test("A stream that ends before message_stop fails the turn")
    func truncatedStream() async throws {
        let run = await stream(.data(SSEFixtures.partialText))

        guard case .networkError? = run.error as? AssistantError else {
            Issue.record("expected a network error, got \(String(describing: run.error))")
            return
        }
    }

    @Test("A stream that stays quiet longer than the idle timeout fails with a timeout")
    func idleTimeout() async throws {
        let run = await stream(.data(SSEFixtures.partialText), .stall, idleTimeout: .milliseconds(200))

        #expect((run.error as? URLError)?.code == .timedOut)
    }

    @Test("A stream that keeps sending outlives the idle timeout")
    func liveStreamIsNotCut() async throws {
        let bytes = Data(SSEFixtures.textOnly.utf8)
        let size = bytes.count / 5 + 1
        let steps: [FakeSSEProtocol.Step] = stride(from: 0, to: bytes.count, by: size).flatMap { start in
            [.pause(0.4), .bytes(bytes[start..<min(start + size, bytes.count)])]
        }
        let run = await stream([FakeSSEProtocol.Script(steps: steps)], idleTimeout: .seconds(1.5))

        #expect(try run.response.content == "Hello")
    }

    @Test("HTTP errors before the stream map to typed errors")
    func httpErrors() async throws {
        let limited = await stream([
            FakeSSEProtocol.Script(status: 429, headers: ["Retry-After": "3"], steps: [.data("{}")])
        ])
        let unauthorized = await stream([FakeSSEProtocol.Script(status: 401, steps: [.data("{}")])])
        let failed = await stream([FakeSSEProtocol.Script(status: 500, steps: [.data("boom")])])

        guard case .rateLimited(let retryAfter)? = limited.error as? AssistantError else {
            Issue.record("expected rate limiting, got \(String(describing: limited.error))")
            return
        }
        #expect(retryAfter == 3)
        guard case .authenticationFailed? = unauthorized.error as? AssistantError else {
            Issue.record("expected an authentication error, got \(String(describing: unauthorized.error))")
            return
        }
        guard case .providerError(let message)? = failed.error as? AssistantError else {
            Issue.record("expected a provider error, got \(String(describing: failed.error))")
            return
        }
        #expect(message == "HTTP 500: boom")
    }

    @Test("sendMessage collects the stream into one response")
    func sendMessageCollects() async throws {
        let (session, baseURL) = FakeSSEProtocol.serving(.data(SSEFixtures.textOnly))
        let provider = ClaudeProvider(apiKey: "test", baseURL: baseURL, session: session)

        let response = try await provider.sendMessage(
            "hi", systemPrompt: "s", conversationHistory: [.user("hi")], tools: [])

        #expect(response.content == "Hello")
    }
}
