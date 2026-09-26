import CADBench
import CADModel
import Foundation

enum Bench {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let tasksDirectory = root.appending(path: "Bench/tasks")

    static func task(_ id: String) throws -> BenchTask { try TaskLoader.load(id: id, from: tasksDirectory) }

    static func check(_ json: String) throws -> Check {
        try JSONDecoder().decode(Check.self, from: Data(json.utf8))
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "cadbench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

func box(
    _ name: String, _ w: Scalar, _ d: Scalar, _ h: Scalar, at translation: Vector3 = Vector3(),
    operation: SolidOperation = .newBody, suppressed: Bool = false
) -> Feature {
    Feature(
        name: name, suppressed: suppressed,
        kind: .primitive(
            PrimitiveFeature(
                .box(width: w, depth: d, height: h), placement: Placement(translation: translation),
                operation: operation)))
}
