import CADAssistantTools
import CADModel
import Foundation
import SwiftUIAssistant

public struct RunSettings: Sendable {
    public var model: String
    public var timeout: Duration
    public var maxToolRounds: Int

    public init(model: String = "claude-opus-5-5", timeout: Duration = .seconds(600), maxToolRounds: Int = 30) {
        self.model = model
        self.timeout = timeout
        self.maxToolRounds = maxToolRounds
    }
}

public enum RunEnd: String, Sendable, Codable {
    case completed, maxToolRounds, timedOut, failed
}

public struct RunRecord: Sendable {
    public let task: String
    public let attempt: Int
    public let end: RunEnd
    public let error: String?
    public let grade: Grade
    public let toolCalls: Int
    public let failedToolCalls: Int
    public let usage: Usage
    public let costUSD: Double?
    public let seconds: Double
    public let listing: String
    public let document: CADDocument
    public let transcript: [TranscriptEntry]

    public var passed: Bool { grade.passed }
}

/// Runs one task through the assistant loop on a fresh session and grades the document it ends with.
@MainActor
public struct BenchRunner<Kernel: GeometryKernel> {
    public let kernel: Kernel
    public let settings: RunSettings
    public let makeProvider: @Sendable () -> any LLMProvider

    public init(kernel: Kernel, settings: RunSettings, makeProvider: @escaping @Sendable () -> any LLMProvider) {
        self.kernel = kernel
        self.settings = settings
        self.makeProvider = makeProvider
    }

    public func run(_ task: BenchTask, attempt: Int) async -> RunRecord {
        let clock = ContinuousClock()
        let start = clock.now
        let session = CADSession(document: task.seed ?? CADDocument(), kernel: kernel)
        if task.seed != nil { _ = try? await session.rebuild() }
        let provider = RecordingProvider(makeProvider())
        var configuration = CADAssistantPrompt.configuration
        configuration.maxToolExecutionRounds = settings.maxToolRounds
        let assistant = Assistant(
            provider: provider, tools: CADTools.all(session: session),
            contextProvider: { session.assistantContext() }, configuration: configuration)

        let (end, error) = await drive(assistant, prompt: task.prompt)
        let seconds = (clock.now - start) / .seconds(1)

        let document = session.document
        _ = await session.currentResult()
        let grade = await Grader(kernel: kernel).grade(task, document: document)
        let usage = await provider.usage
        let messages = assistant.messages
        return RunRecord(
            task: task.id, attempt: attempt, end: end, error: error, grade: grade,
            toolCalls: messages.reduce(0) { $0 + ($1.toolCalls?.count ?? 0) },
            failedToolCalls: messages.count { $0.role == .toolResult && $0.content.hasPrefix("Error: ") },
            usage: usage,
            costUSD: Pricing.cost(
                model: settings.model, inputTokens: usage.inputTokens, outputTokens: usage.outputTokens),
            seconds: seconds, listing: session.listing, document: document,
            transcript: messages.map(TranscriptEntry.init))
    }

    private func drive(_ assistant: Assistant, prompt: String) async -> (RunEnd, String?) {
        let deadline = Deadline()
        let sending = Task { @MainActor in try await assistant.send(prompt) }
        let timer = Task { @MainActor [timeout = settings.timeout] in
            try await Task.sleep(for: timeout)
            deadline.passed = true
            sending.cancel()
        }
        defer { timer.cancel() }
        do {
            try await sending.value
        } catch {
            if deadline.passed { return (.timedOut, nil) }
            return (.failed, (error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
        if deadline.passed { return (.timedOut, nil) }
        return assistant.messages.last?.role == .toolResult ? (.maxToolRounds, nil) : (.completed, nil)
    }
}

@MainActor
private final class Deadline {
    var passed = false
}
