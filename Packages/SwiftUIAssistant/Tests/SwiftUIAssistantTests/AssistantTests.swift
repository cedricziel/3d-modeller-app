import Foundation
@testable import SwiftUIAssistant
import Testing

@Suite("Assistant Tests")
struct AssistantTests {
    @Test("Assistant initialization")
    @MainActor
    func initialization() {
        let provider = MockLLMProvider()
        let assistant = Assistant(
            provider: provider,
            tools: [],
            contextProvider: { MockContext() }
        )

        #expect(assistant.messages.isEmpty)
        #expect(assistant.isProcessing == false)
    }

    @Test("Send message updates state")
    @MainActor
    func sendMessageUpdatesState() async throws {
        let provider = MockLLMProvider()
        await provider.queueTextResponse("Hello back!")

        let assistant = Assistant(
            provider: provider,
            tools: [],
            contextProvider: { MockContext() }
        )

        try await assistant.send("Hello!")

        #expect(assistant.messages.count == 2)  // User + Assistant
        #expect(assistant.messages[0].role == .user)
        #expect(assistant.messages[0].content == "Hello!")
        #expect(assistant.messages[1].role == .assistant)
        #expect(assistant.messages[1].content == "Hello back!")
    }

    @Test("Assistant keeps the provider's raw content on the assistant message")
    @MainActor
    func keepsRawContent() async throws {
        let provider = MockLLMProvider()
        let raw: [JSONValue] = [
            ["type": "thinking", "thinking": "", "signature": "sig-1"],
            ["type": "text", "text": "Hi"],
        ]
        await provider.queueResponse(
            LLMResponse(
                content: "Hi",
                toolCalls: nil,
                stopReason: .endTurn,
                rawContent: raw
            ))

        let assistant = Assistant(
            provider: provider,
            tools: [],
            contextProvider: { MockContext() }
        )

        try await assistant.send("Hello!")

        #expect(assistant.messages[1].rawContent == raw)
    }

    @Test("Assistant executes tool calls")
    @MainActor
    func toolExecution() async throws {
        let provider = MockLLMProvider()

        let executionTracker = ExecutionTracker()
        let tool = MockTool(
            id: "test_tool",
            name: "test_tool",
            description: "Test",
            executeHandler: { _ in
                await executionTracker.markExecuted()
                return ToolExecutionResult(success: true, message: "Done", data: nil)
            }
        )

        let toolCall = ToolCall(
            id: "call_1",
            name: "test_tool",
            arguments: [:]
        )

        await provider.queueToolCallResponse(content: "Executing tool", toolCalls: [toolCall])
        await provider.queueTextResponse("Tool executed successfully")

        let assistant = Assistant(
            provider: provider,
            tools: [tool],
            contextProvider: { MockContext() }
        )

        try await assistant.send("Run the tool")

        let wasExecuted = await executionTracker.wasExecuted
        #expect(wasExecuted)
    }

    @Test("Assistant handles tool execution failure gracefully")
    @MainActor
    func toolExecutionFailure() async throws {
        let provider = MockLLMProvider()

        let failingTool = FailingMockTool(errorMessage: "Something went wrong")

        let toolCall = ToolCall(
            id: "call_1",
            name: "failing_tool",
            arguments: [:]
        )

        await provider.queueToolCallResponse(content: nil, toolCalls: [toolCall])
        await provider.queueTextResponse("I encountered an error")

        let assistant = Assistant(
            provider: provider,
            tools: [failingTool],
            contextProvider: { MockContext() }
        )

        // Should not throw, failures are handled gracefully
        try await assistant.send("Do something")

        // Conversation should continue
        #expect(assistant.messages.count >= 2)
    }

    @Test("Clear history resets conversation")
    @MainActor
    func testClearHistory() async throws {
        let provider = MockLLMProvider()
        await provider.queueTextResponse("Response")

        let assistant = Assistant(
            provider: provider,
            tools: [],
            contextProvider: { MockContext() }
        )

        try await assistant.send("Hello")
        #expect(!assistant.messages.isEmpty)

        assistant.clearHistory()
        #expect(assistant.messages.isEmpty)
    }

    @Test("isProcessing flag during send")
    @MainActor
    func isProcessingFlag() async throws {
        let provider = MockLLMProvider()
        await provider.queueTextResponse("Response")

        // Add small delay to observe processing state
        let delayNs: UInt64 = 50_000_000  // 50ms
        await (provider as MockLLMProvider).setResponseDelay(delayNs)

        let assistant = Assistant(
            provider: provider,
            tools: [],
            contextProvider: { MockContext() }
        )

        #expect(assistant.isProcessing == false)

        let task = Task {
            try await assistant.send("Hello")
        }

        // Give time for processing to start
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        // Note: Due to Swift concurrency, this may or may not catch the processing state
        // The important thing is it should be false after completion

        try await task.value

        #expect(assistant.isProcessing == false)
    }

    @Test("Context provider is called")
    @MainActor
    func contextProviderCalled() async throws {
        let provider = MockLLMProvider()
        await provider.queueTextResponse("Response")

        let contextTracker = ContextCallTracker()
        let assistant = Assistant(
            provider: provider,
            tools: [],
            contextProvider: {
                contextTracker.markCalled()
                return MockContext()
            }
        )

        try await assistant.send("Hello")

        #expect(contextTracker.wasCalled)
    }

    @Test("System prompt includes context")
    @MainActor
    func systemPromptIncludesContext() async throws {
        let provider = MockLLMProvider()
        await provider.queueTextResponse("Response")

        let context = MockContext(description: "Custom context info")

        let assistant = Assistant(
            provider: provider,
            tools: [],
            contextProvider: { context }
        )

        try await assistant.send("Hello")

        let received = await provider.receivedMessages
        #expect(received.first?.systemPrompt.contains("Custom context info") == true)
    }

    @Test("System prompt stays fixed for the whole conversation")
    @MainActor
    func systemPromptFrozenPerConversation() async throws {
        let provider = MockLLMProvider()
        let toolCall = ToolCall(id: "call_1", name: "test_tool", arguments: [:])
        await provider.queueToolCallResponse(content: nil, toolCalls: [toolCall])
        await provider.queueTextResponse("Done")
        await provider.queueTextResponse("Second turn")

        let counter = ContextCounter()
        let tool = MockTool(id: "test_tool", name: "test_tool", description: "Test")
        let assistant = Assistant(
            provider: provider,
            tools: [tool],
            contextProvider: { MockContext(description: "state \(counter.next())") }
        )

        try await assistant.send("First")
        try await assistant.send("Again")

        let prompts = await provider.receivedMessages.map(\.systemPrompt)
        #expect(prompts.count == 3)
        #expect(Set(prompts).count == 1)
    }

    @Test("Clearing history starts a new system prompt")
    @MainActor
    func clearHistoryRebuildsSystemPrompt() async throws {
        let provider = MockLLMProvider()
        await provider.queueTextResponse("One")
        await provider.queueTextResponse("Two")

        let counter = ContextCounter()
        let assistant = Assistant(
            provider: provider,
            tools: [],
            contextProvider: { MockContext(description: "state \(counter.next())") }
        )

        try await assistant.send("First")
        assistant.clearHistory()
        try await assistant.send("Second")

        let prompts = await provider.receivedMessages.map(\.systemPrompt)
        #expect(prompts.count == 2)
        #expect(prompts[0] != prompts[1])
    }
}

final class ContextCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

// MARK: - Mock Context

struct MockContext: AssistantContext {
    let customDescription: String

    init(description: String = "Mock context") {
        customDescription = description
    }

    func serialize() -> [String: Any] {
        return ["mock": true]
    }

    var contextDescription: String {
        customDescription
    }
}

// MARK: - Context Call Tracker

final class ContextCallTracker: @unchecked Sendable {
    private var _wasCalled = false
    private let lock = NSLock()

    var wasCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _wasCalled
    }

    func markCalled() {
        lock.lock()
        defer { lock.unlock() }
        _wasCalled = true
    }
}

// MARK: - Execution Tracker

actor ExecutionTracker {
    private var _wasExecuted = false

    var wasExecuted: Bool {
        _wasExecuted
    }

    func markExecuted() {
        _wasExecuted = true
    }
}

// MARK: - Helper extension for MockLLMProvider

extension MockLLMProvider {
    func setResponseDelay(_ nanoseconds: UInt64) {
        responseDelay = nanoseconds
    }
}
