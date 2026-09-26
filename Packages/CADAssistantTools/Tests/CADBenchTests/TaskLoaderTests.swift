import CADModel
import Foundation
import Testing

@testable import CADBench

@Suite("Task loader")
struct TaskLoaderTests {
    private func write(_ files: [String: String]) throws -> URL {
        let root = try Bench.temporaryDirectory()
        for (path, content) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return root
    }

    private let plate = #"{"format": 1, "units": "mm", "parts": [{"name": "P", "features": []}]}"#

    @Test("Tasks load sorted by id with their seed and reference documents")
    func loadsTasks() throws {
        let root = try write([
            "b/task.json": #"{"kind": "build", "prompt": "Box", "checks": [{"type": "gate"}]}"#,
            "a/task.json":
                #"{"kind": "modify", "prompt": "Edit", "checks": [{"type": "unchangedExcept"}, {"type": "referenceIoU", "threshold": 0.9}]}"#,
            "a/seed.cadmodel": plate,
            "a/reference.cadmodel": plate,
            "notes/readme.txt": "not a task",
        ])

        let tasks = try TaskLoader.loadAll(from: root)

        #expect(tasks.map(\.id) == ["a", "b"])
        #expect(tasks[0].kind == .modify && tasks[0].seed != nil && tasks[0].reference != nil)
        #expect(tasks[1].prompt == "Box" && tasks[1].seed == nil)
        #expect(try TaskLoader.load(id: "b", from: root).checks == [.gate])
    }

    @Test(
        "Inconsistent tasks are refused with the task id",
        arguments: [
            #"{"kind": "modify", "prompt": "x", "checks": [{"type": "gate"}]}"#,
            #"{"kind": "build", "prompt": "x", "checks": [{"type": "referenceIoU", "threshold": 0.9}]}"#,
            #"{"kind": "build", "prompt": "x", "checks": [{"type": "unchangedExcept"}]}"#,
            #"{"kind": "build", "prompt": "x", "checks": []}"#,
            #"{"kind": "build", "prompt": " ", "checks": [{"type": "gate"}]}"#,
            #"{"kind": "build", "prompt": "x", "checks": [{"type": "gate"}], "extra": 1}"#,
            #"{"kind": "build", "prompt": "x", "checks": [{"type": "volume"}]}"#,
        ])
    func loaderRefusals(json: String) throws {
        let root = try write(["t/task.json": json])
        #expect {
            try TaskLoader.load(id: "t", from: root)
        } throws: { error in
            guard case .invalid(let task, _) = error as? TaskLoadError else { return false }
            return task == "t"
        }
    }

    @Test("A build task with a seed and a broken seed document are refused")
    func documentRefusals() throws {
        let root = try write([
            "b/task.json": #"{"kind": "build", "prompt": "x", "checks": [{"type": "gate"}]}"#,
            "b/seed.cadmodel": plate,
            "m/task.json": #"{"kind": "modify", "prompt": "x", "checks": [{"type": "gate"}]}"#,
            "m/seed.cadmodel": #"{"format": 9}"#,
        ])
        #expect(throws: TaskLoadError.self) { try TaskLoader.load(id: "b", from: root) }
        #expect(throws: TaskLoadError.self) { try TaskLoader.load(id: "m", from: root) }
    }

    @Test("An unknown task id is refused")
    func unknownTask() throws {
        let root = try write([:])
        #expect(throws: TaskLoadError.notFound("missing")) { try TaskLoader.load(id: "missing", from: root) }
    }
}
