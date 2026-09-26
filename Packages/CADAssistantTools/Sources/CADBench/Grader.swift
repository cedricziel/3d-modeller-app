import CADModel
import Foundation

public struct CheckOutcome: Sendable, Codable, Equatable {
    public let check: String
    public let passed: Bool
    public let detail: String

    public init(check: String, passed: Bool, detail: String) {
        self.check = check
        self.passed = passed
        self.detail = detail
    }
}

public struct Grade: Sendable, Codable, Equatable {
    public let outcomes: [CheckOutcome]
    public let passed: Bool

    public init(outcomes: [CheckOutcome]) {
        self.outcomes = outcomes
        passed = !outcomes.isEmpty && outcomes.allSatisfy(\.passed)
    }

    public var failures: [CheckOutcome] { outcomes.filter { !$0.passed } }
}

public struct Grader<Kernel: GeometryKernel>: Sendable {
    public let kernel: Kernel
    public let sketchSolver: (any SketchSolving)?

    public init(kernel: Kernel, sketchSolver: (any SketchSolving)? = nil) {
        self.kernel = kernel
        self.sketchSolver = sketchSolver
    }

    public func grade(_ task: BenchTask, document: CADDocument) async -> Grade {
        let result: RebuildResult
        do {
            result = try await RebuildEngine(kernel: kernel, sketchSolver: sketchSolver).rebuild(document)
        } catch {
            return Grade(
                outcomes: task.checks.map {
                    CheckOutcome(check: $0.description, passed: false, detail: "rebuild failed: \(error)")
                })
        }
        var outcomes: [CheckOutcome] = []
        for check in task.checks {
            let (passed, detail) = await evaluate(check, task: task, document: document, result: result)
            outcomes.append(CheckOutcome(check: check.description, passed: passed, detail: detail))
        }
        return Grade(outcomes: outcomes)
    }

    private func evaluate(
        _ check: Check, task: BenchTask, document: CADDocument, result: RebuildResult
    ) async -> (Bool, String) {
        switch check {
        case .gate:
            return gate(result)
        case .bodyCount(let expected):
            let count = result.bodies.count
            return (count == expected, count == 1 ? "1 body" : "\(count) bodies")
        case .boundingBox(let selector, let min, let max, let size, let tolerance):
            let bodies: [BodyResult]
            switch select(selector, in: result) {
            case .success(let selected): bodies = selected
            case .failure(let problem): return (false, problem.message)
            }
            guard let bounds = Self.bounds(of: bodies) else { return (false, "a selected body has no measurements") }
            func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>?) -> Bool {
                guard let b else { return true }
                let delta = a - b
                return abs(delta.x) <= tolerance && abs(delta.y) <= tolerance && abs(delta.z) <= tolerance
            }
            let passed = close(bounds.min, min) && close(bounds.max, max) && close(bounds.max - bounds.min, size)
            return (passed, "min \(BenchFormat.vector(bounds.min)), max \(BenchFormat.vector(bounds.max))")
        case .volume(let selector, let expected, let tolerance):
            let bodies: [BodyResult]
            switch select(selector, in: result) {
            case .success(let selected): bodies = selected
            case .failure(let problem): return (false, problem.message)
            }
            let volumes = bodies.map { $0.metrics?.volume }
            guard volumes.allSatisfy({ $0 != nil }) else { return (false, "a selected body has no volume") }
            let volume = volumes.compactMap { $0 }.reduce(0, +)
            return (abs(volume - expected) <= tolerance * abs(expected), "\(BenchFormat.number(volume)) mm³")
        case .parameter(let name, let expected, let tolerance):
            switch result.parameters.value(of: name) {
            case nil: return (false, "no parameter named \(name)")
            case .failure(let error)?: return (false, "\(name) does not evaluate: \(error)")
            case .success(let value)?:
                return (abs(value - expected) <= tolerance, "\(name) = \(BenchFormat.number(value))")
            }
        case .featureCount(let type, let min, let max):
            let count = document.parts.flatMap(\.features).count { !$0.suppressed && FeatureType($0.kind) == type }
            let passed = count >= (min ?? 0) && count <= (max ?? .max)
            return (passed, "\(count) \(type.rawValue) feature\(count == 1 ? "" : "s")")
        case .referenceIoU(let threshold):
            guard let reference = task.reference else { return (false, "the task has no reference") }
            do {
                guard let overlap = try await overlap(document, reference) else { return (false, "no bodies") }
                let detail =
                    "overlap \(BenchFormat.number(overlap.ratio)) (intersection "
                    + "\(BenchFormat.number(overlap.intersection)) mm³, union \(BenchFormat.number(overlap.union)) mm³)"
                return (overlap.ratio >= threshold, detail)
            } catch {
                return (false, "overlap could not be computed: \(error)")
            }
        case .unchangedExcept(let features, let parameters, let allowNewFeatures):
            guard let seed = task.seed else { return (false, "the task has no seed") }
            let differences = DocumentComparison.differences(
                from: seed, to: document, features: Set(features), parameters: Set(parameters),
                allowNewFeatures: allowNewFeatures)
            return (differences.isEmpty, differences.isEmpty ? "unchanged" : differences.joined(separator: "; "))
        }
    }

    private func gate(_ result: RebuildResult) -> (Bool, String) {
        let qualified = result.parts.count > 1
        func label(_ part: PartResult, _ name: String) -> String { qualified ? "\(part.name)/\(name)" : name }
        var problems: [String] = []
        for part in result.parts {
            for feature in part.features {
                switch feature.status {
                case .failed, .skipped: problems.append("\(label(part, feature.name)): \(feature.status)")
                case .ok, .suppressed: continue
                }
            }
            for body in part.bodies {
                if let problem = Self.problem(with: body) { problems.append("\(label(part, body.name)): \(problem)") }
            }
        }
        if result.bodies.isEmpty { problems.append("no bodies") }
        return (problems.isEmpty, problems.isEmpty ? "ok" : problems.joined(separator: "; "))
    }

    private static func problem(with body: BodyResult) -> String? {
        if let error = body.error { return error }
        guard let metrics = body.metrics else { return "no measurements" }
        if !metrics.isValid { return "invalid shape" }
        if !metrics.isClosed { return "not closed" }
        if metrics.solidCount != 1 { return "\(metrics.solidCount) solids" }
        return nil
    }

    private struct SelectionProblem: Error {
        let message: String
    }

    private func select(_ selector: BodySelector, in result: RebuildResult) -> Result<[BodyResult], SelectionProblem> {
        var parts = result.parts
        if let name = selector.part {
            parts = parts.filter { $0.name == name }
            guard !parts.isEmpty else {
                let names = result.parts.map(\.name).joined(separator: ", ")
                return .failure(.init(message: "no part named \(name) (parts: \(names))"))
            }
        }
        guard let bodyName = selector.body else {
            let bodies = parts.flatMap(\.bodies)
            return bodies.isEmpty ? .failure(.init(message: "no bodies")) : .success(bodies)
        }
        let matches = parts.filter { $0.bodies.contains { $0.name == bodyName } }
        switch matches.count {
        case 0:
            let all = parts.flatMap { part in part.bodies.map { "\(part.name)/\($0.name)" } }
            let names = all.isEmpty ? "none" : all.joined(separator: ", ")
            return .failure(.init(message: "no body named \(bodyName) (bodies: \(names))"))
        case 1:
            return .success(matches[0].bodies.filter { $0.name == bodyName })
        default:
            let names = matches.map(\.name).joined(separator: ", ")
            return .failure(.init(message: "\(bodyName) exists in \(names); name the part"))
        }
    }

    private static func bounds(of bodies: [BodyResult]) -> (min: SIMD3<Double>, max: SIMD3<Double>)? {
        let metrics = bodies.map(\.metrics)
        guard !metrics.isEmpty, metrics.allSatisfy({ $0 != nil }) else { return nil }
        let all = metrics.compactMap { $0 }
        return (
            all.dropFirst().reduce(all[0].boundsMin) { pointwiseMin($0, $1.boundsMin) },
            all.dropFirst().reduce(all[0].boundsMax) { pointwiseMax($0, $1.boundsMax) }
        )
    }

    private struct Overlap {
        let intersection: Double
        let union: Double
        var ratio: Double { union > 0 ? intersection / union : 0 }
    }

    /// Intersection over union by inclusion–exclusion, because an empty intersection is a kernel error.
    private func overlap(_ document: CADDocument, _ reference: CADDocument) async throws -> Overlap? {
        let engine = RebuildEngine(kernel: kernel, sketchSolver: sketchSolver)
        let candidate = try await engine.solids(of: document).map(\.body)
        let expected = try await engine.solids(of: reference).map(\.body)
        guard let a = try fuse(candidate), let b = try fuse(expected) else { return nil }
        let union = try kernel.boolean(.union, a, b, feature: "Overlap")
        let (va, vb, vu) = (try volume(a), try volume(b), try volume(union))
        return Overlap(intersection: max(0, va + vb - vu), union: vu)
    }

    private func fuse(_ bodies: [Kernel.Body]) throws -> Kernel.Body? {
        guard var fused = bodies.first else { return nil }
        for body in bodies.dropFirst() { fused = try kernel.boolean(.union, fused, body, feature: "Overlap") }
        return fused
    }

    private func volume(_ body: Kernel.Body) throws -> Double {
        try kernel.metrics(of: body).volume ?? 0
    }
}
