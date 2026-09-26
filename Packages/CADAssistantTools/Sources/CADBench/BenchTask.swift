import CADModel
import Foundation

public enum TaskKind: String, Sendable, Codable {
    case build, modify
}

public struct BenchTask: Sendable {
    public let id: String
    public let kind: TaskKind
    public let prompt: String
    public let checks: [Check]
    public let seed: CADDocument?
    public let reference: CADDocument?

    public init(
        id: String, kind: TaskKind, prompt: String, checks: [Check], seed: CADDocument? = nil,
        reference: CADDocument? = nil
    ) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.checks = checks
        self.seed = seed
        self.reference = reference
    }
}

public enum TaskLoadError: Error, Equatable, CustomStringConvertible {
    case notFound(String)
    case invalid(task: String, reason: String)

    public var description: String {
        switch self {
        case .notFound(let id): "No task named '\(id)'"
        case .invalid(let task, let reason): "Task '\(task)' is invalid: \(reason)"
        }
    }
}

public enum TaskLoader {
    private struct TaskFile: Decodable {
        let kind: TaskKind
        let prompt: String
        let checks: [Check]
    }

    public static func loadAll(from directory: URL) throws -> [BenchTask] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return
            try entries
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "task.json").path) }
            .map(\.lastPathComponent)
            .sorted()
            .map { try load(id: $0, from: directory) }
    }

    public static func load(id: String, from directory: URL) throws -> BenchTask {
        let folder = directory.appending(path: id)
        let taskURL = folder.appending(path: "task.json")
        guard !id.contains("/"), FileManager.default.fileExists(atPath: taskURL.path) else {
            throw TaskLoadError.notFound(id)
        }
        func invalid(_ reason: String) -> TaskLoadError { .invalid(task: id, reason: reason) }
        let file: TaskFile
        do {
            let data = try Data(contentsOf: taskURL)
            let keys = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let unknown = Set(keys.keys).subtracting(["kind", "prompt", "checks"]).sorted()
            guard unknown.isEmpty else { throw invalid("unknown keys \(unknown.joined(separator: ", "))") }
            file = try JSONDecoder().decode(TaskFile.self, from: data)
        } catch let error as TaskLoadError {
            throw error
        } catch {
            throw invalid(String(describing: error))
        }
        func document(_ name: String) throws -> CADDocument? {
            let url = folder.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            do { return try CADDocument(json: Data(contentsOf: url)) } catch {
                throw invalid("\(name): \(error)")
            }
        }
        let task = BenchTask(
            id: id, kind: file.kind, prompt: file.prompt, checks: file.checks, seed: try document("seed.cadmodel"),
            reference: try document("reference.cadmodel"))
        if let reason = problem(with: task) { throw invalid(reason) }
        return task
    }

    private static func problem(with task: BenchTask) -> String? {
        if task.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "the prompt is empty" }
        if task.checks.isEmpty { return "it has no checks" }
        switch task.kind {
        case .modify where task.seed == nil: return "a modify task needs seed.cadmodel"
        case .build where task.seed != nil: return "a build task starts empty and cannot have seed.cadmodel"
        default: break
        }
        for check in task.checks {
            switch check {
            case .referenceIoU where task.reference == nil: return "referenceIoU needs reference.cadmodel"
            case .unchangedExcept where task.seed == nil: return "unchangedExcept needs seed.cadmodel"
            default: continue
            }
        }
        return nil
    }
}
