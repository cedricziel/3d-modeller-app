import Foundation

public enum PassAtK {
    /// The unbiased estimate of the chance that at least one of k samples passes, from n samples with c passes.
    public static func estimate(samples n: Int, passes c: Int, k: Int) -> Double {
        guard n > 0, k > 0, c > 0 else { return 0 }
        if n - c < k { return 1 }
        var failAll = 1.0
        for i in (n - c + 1)...n { failAll *= 1 - Double(k) / Double(i) }
        return 1 - failAll
    }
}

public struct RunSummary: Sendable, Codable, Equatable {
    public let task: String
    public let attempt: Int
    public let passed: Bool
    public let end: RunEnd
    public let error: String?
    public let toolCalls: Int
    public let failedToolCalls: Int
    public let requests: Int
    public let retries: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let costUSD: Double?
    public let seconds: Double
    public let outcomes: [CheckOutcome]
    /// Why `final.step` is missing.
    public let exportError: String?

    public init(_ record: RunRecord) {
        task = record.task
        attempt = record.attempt
        passed = record.passed
        end = record.end
        error = record.error
        toolCalls = record.toolCalls
        failedToolCalls = record.failedToolCalls
        requests = record.usage.requests
        retries = record.usage.retries
        inputTokens = record.usage.inputTokens
        outputTokens = record.usage.outputTokens
        costUSD = record.costUSD
        seconds = record.seconds
        outcomes = record.grade.outcomes
        exportError = record.exportError
    }
}

public struct TaskSummary: Sendable, Codable, Equatable {
    public let task: String
    public let kind: TaskKind
    public let runs: Int
    public let passes: Int
    public let passAt1: Double
    public let passAtK: Double
    public let meanToolCalls: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let costUSD: Double?
    public let meanSeconds: Double
}

public struct BenchSummary: Sendable, Codable, Equatable {
    public let model: String
    public let startedAt: String
    public let repeatCount: Int
    public let tasks: [TaskSummary]
    public let runs: [RunSummary]
    public let passAt1: Double
    public let passAtK: Double
    public let costUSD: Double?

    public init(model: String, startedAt: String, repeatCount: Int, tasks: [BenchTask], records: [RunRecord]) {
        self.model = model
        self.startedAt = startedAt
        self.repeatCount = repeatCount
        runs = records.map(RunSummary.init)
        self.tasks = tasks.map { task in
            let own = records.filter { $0.task == task.id }
            let passes = own.count(where: \.passed)
            let count = Double(max(own.count, 1))
            return TaskSummary(
                task: task.id, kind: task.kind, runs: own.count, passes: passes,
                passAt1: PassAtK.estimate(samples: own.count, passes: passes, k: 1),
                passAtK: PassAtK.estimate(samples: own.count, passes: passes, k: min(repeatCount, own.count)),
                meanToolCalls: Double(own.reduce(0) { $0 + $1.toolCalls }) / count,
                inputTokens: own.reduce(0) { $0 + $1.usage.inputTokens },
                outputTokens: own.reduce(0) { $0 + $1.usage.outputTokens },
                costUSD: Self.total(own.map(\.costUSD)),
                meanSeconds: own.reduce(0) { $0 + $1.seconds } / count)
        }
        let taskCount = Double(max(self.tasks.count, 1))
        passAt1 = self.tasks.reduce(0) { $0 + $1.passAt1 } / taskCount
        passAtK = self.tasks.reduce(0) { $0 + $1.passAtK } / taskCount
        costUSD = Self.total(self.tasks.map(\.costUSD))
    }

    private static func total(_ costs: [Double?]) -> Double? {
        costs.contains(nil) ? nil : costs.compactMap { $0 }.reduce(0, +)
    }

    public var markdown: String {
        func cost(_ value: Double?) -> String { value.map { String(format: "$%.2f", $0) } ?? "n/a" }
        let runsPerTask = "\(repeatCount) run\(repeatCount == 1 ? "" : "s") per task"
        var lines = [
            "# cadbench \(startedAt)", "",
            "Model \(model), \(runsPerTask): pass@1 \(BenchFormat.number(passAt1)), "
                + "pass@\(repeatCount) \(BenchFormat.number(passAtK)), cost \(cost(costUSD)).",
            "",
            "| Task | Kind | Passes | pass@1 | pass@\(repeatCount) | Tool calls | Tokens in / out | Cost | Time |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
        for task in tasks {
            let cells = [
                task.task, task.kind.rawValue, "\(task.passes)/\(task.runs)", BenchFormat.number(task.passAt1),
                BenchFormat.number(task.passAtK), BenchFormat.number(task.meanToolCalls),
                "\(task.inputTokens) / \(task.outputTokens)", cost(task.costUSD),
                "\(BenchFormat.number(task.meanSeconds.rounded())) s",
            ]
            lines.append("| \(cells.joined(separator: " | ")) |")
        }
        let failed = runs.filter { !$0.passed }
        if !failed.isEmpty {
            lines += ["", "## Failures", ""]
            for run in failed {
                var reasons = run.outcomes.filter { !$0.passed }.map { "\($0.check): \($0.detail)" }
                if run.end != .completed {
                    reasons.insert("ended: \(run.end.rawValue)\(run.error.map { " (\($0))" } ?? "")", at: 0)
                }
                lines.append("- \(run.task) run \(run.attempt): \(reasons.joined(separator: "; "))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
