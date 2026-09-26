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
    /// Pictures of the final document.
    public let renders: [RenderedView]
    /// The final document exported as STEP, when the export succeeded.
    public var step: Data? = nil
    /// Why the final document could not be exported as STEP.
    public var exportError: String? = nil

    public var passed: Bool { grade.passed }
}

/// Runs one task through the assistant loop on a fresh session and grades the document it ends with.
@MainActor
public struct BenchRunner<Kernel: GeometryKernel> {
    public let kernel: Kernel
    public let sketchSolver: (any SketchSolving)?
    public let assemblySolver: (any AssemblySolving)?
    public let settings: RunSettings
    public let makeProvider: @Sendable () -> any LLMProvider

    public init(
        kernel: Kernel, sketchSolver: (any SketchSolving)? = nil, assemblySolver: (any AssemblySolving)? = nil,
        settings: RunSettings, makeProvider: @escaping @Sendable () -> any LLMProvider
    ) {
        self.kernel = kernel
        self.sketchSolver = sketchSolver
        self.assemblySolver = assemblySolver
        self.settings = settings
        self.makeProvider = makeProvider
    }

    /// `exportDirectory` is the folder the `export` tool may write into during the run.
    public func run(_ task: BenchTask, attempt: Int, exportDirectory: URL? = nil) async -> RunRecord {
        let clock = ContinuousClock()
        let start = clock.now
        let session = CADSession(
            document: task.seed ?? CADDocument(), kernel: kernel, sketchSolver: sketchSolver,
            assemblySolver: assemblySolver)
        session.exportDirectory = exportDirectory
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
        let grade = await Grader(kernel: kernel, sketchSolver: sketchSolver, assemblySolver: assemblySolver).grade(
            task, document: document)
        let renders = await session.renderViews().views
        let (step, exportError) = await Self.finalStep(session)
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
            transcript: messages.map(TranscriptEntry.init), renders: renders, step: step, exportError: exportError)
    }

    private static func finalStep(_ session: CADSession) async -> (Data?, String?) {
        let url = FileManager.default.temporaryDirectory.appending(path: "cadbench-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await session.export(.document, as: .step, to: url)
            return (try Data(contentsOf: url), nil)
        } catch {
            return (nil, String(describing: error))
        }
    }

    /// Races the conversation against the timeout. A provider that ignores cancellation is left behind rather
    /// than awaited, so a stalled run still ends on time.
    private func drive(_ assistant: Assistant, prompt: String) async -> (RunEnd, String?) {
        let gate = RunGate()
        let sending = Task { @MainActor in
            do {
                try await assistant.send(prompt)
                gate.settle(.finished)
            } catch {
                gate.settle(.failed((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }
        let timer = Task { @MainActor [timeout = settings.timeout] in
            try await Task.sleep(for: timeout)
            gate.settle(.timedOut)
        }
        let outcome = await gate.wait()
        timer.cancel()
        switch outcome {
        case .timedOut:
            sending.cancel()
            return (.timedOut, nil)
        case .failed(let message):
            return (.failed, message)
        case .finished:
            return assistant.messages.last?.role == .toolResult ? (.maxToolRounds, nil) : (.completed, nil)
        }
    }
}

@MainActor
private final class RunGate {
    enum Outcome {
        case finished
        case failed(String)
        case timedOut
    }

    private var settled: Outcome?
    private var waiter: CheckedContinuation<Outcome, Never>?

    func settle(_ outcome: Outcome) {
        guard settled == nil else { return }
        settled = outcome
        waiter?.resume(returning: outcome)
        waiter = nil
    }

    func wait() async -> Outcome {
        if let settled { return settled }
        return await withCheckedContinuation { waiter = $0 }
    }
}
