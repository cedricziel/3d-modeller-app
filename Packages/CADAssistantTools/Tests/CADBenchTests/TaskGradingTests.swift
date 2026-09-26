import CADModel
import CADModelKernel
import Testing

@testable import CADBench

enum WrongSolution: String, CaseIterable, Sendable {
    case plateHoleTooSmall, washerBoreTooSmall, flangeNotJoined, pocketTooDeep, uprightOnFarEdge, fullSphere
    case thicknessEditedDirectly, holeMovedAlongY, extraFeatureInMove, secondHoleMisplaced

    var task: String {
        switch self {
        case .plateHoleTooSmall: "plate-hole"
        case .washerBoreTooSmall: "washer"
        case .flangeNotJoined: "flanged-shaft"
        case .pocketTooDeep: "block-pocket"
        case .uprightOnFarEdge: "l-bracket"
        case .fullSphere: "hemisphere"
        case .thicknessEditedDirectly: "plate-thickness"
        case .holeMovedAlongY, .extraFeatureInMove: "plate-move-hole"
        case .secondHoleMisplaced: "plate-second-hole"
        }
    }

    /// The check that must catch the mistake.
    var failingCheck: String {
        switch self {
        case .plateHoleTooSmall, .washerBoreTooSmall, .pocketTooDeep: "volume"
        case .flangeNotJoined: "body count"
        case .uprightOnFarEdge, .holeMovedAlongY, .secondHoleMisplaced: "overlap"
        case .fullSphere: "bounding box"
        case .thicknessEditedDirectly: "parameter t"
        case .extraFeatureInMove: "unchanged"
        }
    }

    func document(from task: BenchTask) throws -> CADDocument {
        let reference = try #require(task.reference)
        switch self {
        case .plateHoleTooSmall:
            return reference.editing("Hole") { $0.setShape(.cylinder(radius: 4, height: "t + 2")) }
        case .washerBoreTooSmall:
            return reference.editing("Bore") { $0.setShape(.cylinder(radius: 6, height: 4.5)) }
        case .flangeNotJoined:
            return reference.removing("Union")
        case .pocketTooDeep:
            return reference.editing("Pocket") { $0.setTranslation(Vector3(15, 10, 10)) }
        case .uprightOnFarEdge:
            return reference.editing("Upright") { $0.setTranslation(Vector3(0, 35, 0)) }
        case .fullSphere:
            return reference.removing("Half")
        case .thicknessEditedDirectly:
            return try #require(task.seed)
                .editing("Plate") { $0.setShape(.box(width: "width", depth: "depth", height: 10)) }
                .editing("Hole") { $0.setShape(.cylinder(radius: "hole_d / 2", height: 12)) }
        case .holeMovedAlongY:
            return try #require(task.seed).editing("Hole") {
                $0.setTranslation(Vector3("width / 2", "depth / 2 + 10", -1))
            }
        case .extraFeatureInMove:
            var document = reference
            document.parts[0].features.append(box("Boss", 5, 5, 5, at: Vector3(0, 0, 6), operation: .join("Body1")))
            return document
        case .secondHoleMisplaced:
            return reference.editing("Hole2") { $0.setTranslation(Vector3(60, "depth / 2", -1)) }
        }
    }
}

extension CADDocument {
    func editing(_ name: String, _ change: (inout FeatureKind) -> Void) -> CADDocument {
        var copy = self
        for part in copy.parts.indices {
            for index in copy.parts[part].features.indices where copy.parts[part].features[index].name == name {
                change(&copy.parts[part].features[index].kind)
            }
        }
        return copy
    }

    func removing(_ name: String) -> CADDocument {
        var copy = self
        for part in copy.parts.indices { copy.parts[part].features.removeAll { $0.name == name } }
        return copy
    }
}

extension FeatureKind {
    mutating func setShape(_ shape: PrimitiveShape) {
        guard case .primitive(var primitive) = self else { return }
        primitive.shape = shape
        self = .primitive(primitive)
    }

    mutating func setTranslation(_ translation: Vector3) {
        guard case .primitive(var primitive) = self else { return }
        primitive.placement.translation = translation
        self = .primitive(primitive)
    }
}

@Suite("Seed tasks")
struct TaskGradingTests {
    static let ids = [
        "block-pocket", "flanged-shaft", "hemisphere", "l-bracket", "plate-hole", "plate-move-hole",
        "plate-second-hole", "plate-thickness", "washer",
    ]
    let grader = Grader(kernel: OCCTGeometryKernel())

    @Test("Every task directory loads")
    func allLoad() throws {
        #expect(try TaskLoader.loadAll(from: Bench.tasksDirectory).map(\.id) == Self.ids)
    }

    @Test("Each task's reference document passes all its checks", arguments: ids)
    func referencePasses(id: String) async throws {
        let task = try Bench.task(id)
        let grade = await grader.grade(task, document: try #require(task.reference))
        #expect(grade.passed, "\(grade.failures)")
    }

    @Test("A modify task's untouched seed fails", arguments: ids)
    func untouchedSeedFails(id: String) async throws {
        let task = try Bench.task(id)
        guard let seed = task.seed else { return }
        let grade = await grader.grade(task, document: seed)
        #expect(!grade.passed)
    }

    @Test("A deliberately wrong solution fails the check meant to catch it", arguments: WrongSolution.allCases)
    func wrongSolutionFails(wrong: WrongSolution) async throws {
        let task = try Bench.task(wrong.task)
        let grade = await grader.grade(task, document: try wrong.document(from: task))
        #expect(!grade.passed)
        #expect(grade.failures.contains { $0.check.contains(wrong.failingCheck) }, "\(grade.outcomes)")
    }
}
