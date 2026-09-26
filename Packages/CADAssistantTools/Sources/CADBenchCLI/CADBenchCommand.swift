import CADBench
import CADModel
import CADModelKernel
import CADModelSolvers
import Foundation
import SwiftUIAssistant

@main
struct CADBenchCommand {
    static func main() async {
        do {
            let command = try BenchCommand.parse(Array(CommandLine.arguments.dropFirst()))
            exit(try await run(command))
        } catch let error as UsageError {
            printError("\(error)\n\n\(BenchCommand.usage)")
            exit(2)
        } catch {
            printError("\(error)")
            exit(1)
        }
    }

    @MainActor
    static func run(_ command: BenchCommand) async throws -> Int32 {
        switch command {
        case .help:
            print(BenchCommand.usage)
            return 0
        case .list(let directory):
            for task in try TaskLoader.loadAll(from: URL(filePath: directory)) {
                let firstLine = task.prompt.split(separator: "\n").first.map(String.init) ?? ""
                print("\(task.id)\t\(task.kind.rawValue)\t\(firstLine)")
            }
            return 0
        case .grade(let id, let path, let directory):
            let task = try TaskLoader.load(id: id, from: URL(filePath: directory))
            let document = try CADDocument(json: Data(contentsOf: URL(filePath: path)))
            let grade = await Grader(kernel: OCCTGeometryKernel(), sketchSolver: PlaneGCSSketchSolver()).grade(
                task, document: document)
            for outcome in grade.outcomes {
                print("\(outcome.passed ? "PASS" : "FAIL")  \(outcome.check) — \(outcome.detail)")
            }
            print(grade.passed ? "\(id): passed" : "\(id): failed")
            return grade.passed ? 0 : 1
        case .run(let options):
            return try await runBench(options)
        }
    }

    @MainActor
    static func runBench(_ options: RunOptions) async throws -> Int32 {
        let key = try APIKey.resolve(
            environment: ProcessInfo.processInfo.environment, useAppKey: options.useAppKey,
            savedInApp: APIKey.savedInApp)
        let redact = Redactor(secrets: [key])
        let directory = URL(filePath: options.tasksDirectory)
        let tasks =
            try options.taskIDs.map { ids in try ids.map { try TaskLoader.load(id: $0, from: directory) } }
            ?? TaskLoader.loadAll(from: directory)
        let startedAt = BenchClock.timestamp(Date())
        let output = URL(filePath: options.outputDirectory).appending(path: startedAt)
        let writer = ResultWriter(directory: output, redactor: redact)
        let model = options.model
        let effort = options.effort
        let runner = BenchRunner(
            kernel: OCCTGeometryKernel(), sketchSolver: PlaneGCSSketchSolver(),
            settings: RunSettings(
                model: model, timeout: .seconds(options.timeoutSeconds), maxToolRounds: options.maxToolRounds),
            makeProvider: { ClaudeProvider(apiKey: key, model: model, effort: effort) })

        printError("cadbench: \(tasks.count) task(s) × \(options.repeatCount) with \(model), results in \(output.path)")
        var records: [RunRecord] = []
        for task in tasks {
            for attempt in 1...options.repeatCount {
                let record = await runner.run(task, attempt: attempt)
                try writer.write(record)
                records.append(record)
                let verdict = record.passed ? "PASS" : "FAIL"
                let end = record.end == .completed ? "" : " [\(record.end.rawValue)]"
                let seconds = Int(record.seconds.rounded())
                printError("\(task.id) #\(attempt): \(verdict)\(end), \(record.toolCalls) tool calls, \(seconds) s")
            }
        }
        let summary = BenchSummary(
            model: model, startedAt: startedAt, repeatCount: options.repeatCount, tasks: tasks, records: records)
        try writer.write(summary)
        print(redact(summary.markdown))
        return 0
    }

    static func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
