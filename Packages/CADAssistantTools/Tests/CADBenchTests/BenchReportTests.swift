import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADBench

@Suite("Report")
struct BenchReportTests {
    @Test("pass@k follows the unbiased estimator")
    func passAtK() {
        #expect(PassAtK.estimate(samples: 3, passes: 0, k: 1) == 0)
        #expect(PassAtK.estimate(samples: 3, passes: 3, k: 1) == 1)
        #expect(abs(PassAtK.estimate(samples: 4, passes: 1, k: 1) - 0.25) < 1e-12)
        #expect(abs(PassAtK.estimate(samples: 4, passes: 1, k: 2) - 0.5) < 1e-12)
        #expect(PassAtK.estimate(samples: 4, passes: 1, k: 4) == 1)
        #expect(PassAtK.estimate(samples: 0, passes: 0, k: 1) == 0)
    }

    private func record(_ task: String, _ attempt: Int, passed: Bool, secret: String = "") -> RunRecord {
        let outcome = CheckOutcome(check: "volume", passed: passed, detail: passed ? "ok" : "6100 mm³")
        return RunRecord(
            task: task, attempt: attempt, end: .completed, error: nil, grade: Grade(outcomes: [outcome]),
            toolCalls: 4, failedToolCalls: 1, usage: Usage(requests: 2, inputTokens: 1000, outputTokens: 100),
            costUSD: 0.01, seconds: 2, listing: "part P\n  (no features) \(secret)",
            document: CADDocument(parts: [Part(name: "P \(secret)")]),
            transcript: [TranscriptEntry(.user("hello \(secret)"))])
    }

    private let tasks = [
        BenchTask(id: "a", kind: .build, prompt: "p", checks: [.gate]),
        BenchTask(id: "b", kind: .modify, prompt: "p", checks: [.gate], seed: CADDocument()),
    ]

    @Test("The summary aggregates runs per task and overall")
    func summary() {
        let summary = BenchSummary(
            model: "claude-opus-5-5", startedAt: "2026-09-26T10-00-00Z", repeatCount: 2, tasks: tasks,
            records: [
                record("a", 1, passed: true), record("a", 2, passed: false), record("b", 1, passed: false),
                record("b", 2, passed: false),
            ])
        #expect(summary.tasks.map(\.passes) == [1, 0])
        #expect(summary.tasks[0].passAt1 == 0.5 && summary.tasks[0].passAtK == 1)
        #expect(summary.passAt1 == 0.25 && summary.passAtK == 0.5)
        #expect(summary.costUSD == 0.04)
        #expect(summary.tasks[0].inputTokens == 2000 && summary.tasks[0].meanToolCalls == 4)
        let markdown = summary.markdown
        #expect(markdown.contains("| a | build | 1/2 | 0.5 | 1 | 4 | 2000 / 200 | $0.02 | 2 s |"))
        #expect(markdown.contains("pass@1 0.25, pass@2 0.5"))
        #expect(markdown.contains("- b run 1: volume: 6100 mm³"))
    }

    @Test("Results are written per run and the secret never reaches a file")
    func writerRedactsSecrets() throws {
        let secret = "sk-ant-test-secret-123"
        let directory = try Bench.temporaryDirectory()
        let writer = ResultWriter(directory: directory, redactor: Redactor(secrets: [secret]))
        let run = record("a", 1, passed: true, secret: secret)
        try writer.write(run)
        try writer.write(BenchSummary(model: "m", startedAt: "t", repeatCount: 1, tasks: tasks, records: [run]))

        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted()
        for expected in [
            "a/run-1/document.cadmodel", "a/run-1/transcript.json", "a/run-1/listing.txt", "a/run-1/run.json",
            "summary.json", "summary.md",
        ] {
            #expect(files.contains(expected), "\(expected)")
        }
        for file in files {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: directory.appending(path: file).path, isDirectory: &isDirectory)
            if isDirectory.boolValue { continue }
            let text = try String(contentsOf: directory.appending(path: file), encoding: .utf8)
            #expect(!text.contains(secret), "\(file)")
        }
        let transcript = try String(contentsOf: directory.appending(path: "a/run-1/transcript.json"), encoding: .utf8)
        #expect(transcript.contains("[redacted]"))
        let document = try CADDocument(json: Data(contentsOf: directory.appending(path: "a/run-1/document.cadmodel")))
        #expect(document.parts[0].name == "P [redacted]")
    }

    @Test("Timestamps contain no colons")
    func timestamp() {
        #expect(BenchClock.timestamp(Date(timeIntervalSince1970: 0)) == "1970-01-01T00-00-00Z")
    }
}
