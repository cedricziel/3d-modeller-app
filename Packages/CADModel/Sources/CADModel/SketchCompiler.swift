import Foundation

extension SketchFeature {
    /// Checks names, counts and values without solving; throws the error the rebuild would report.
    public func check(parameters: ParameterTable) throws(FeatureError) {
        _ = try SketchCompiler.compile(self, parameters: parameters)
    }
}

/// Turns a sketch's names, expressions and degrees into a `SolverSketch`, and a solution back into entities.
enum SketchCompiler {
    static func compile(_ sketch: SketchFeature, parameters: ParameterTable) throws(FeatureError) -> SolverSketch {
        var indices: [String: Int] = [:]
        for (index, entity) in sketch.entities.enumerated() {
            guard indices.updateValue(index, forKey: entity.name) == nil else {
                throw .sketch("more than one entity named '\(entity.name)'")
            }
            if let problem = entity.geometry.problem { throw .sketch("\(entity.name): \(problem)") }
        }
        var entities = sketch.entities.map { SolverEntity(geometry: $0.geometry.solver, construction: $0.construction) }
        var names = Set<String>()
        var constraints: [SolverConstraint] = []
        for constraint in sketch.constraints {
            guard names.insert(constraint.name).inserted else {
                throw .sketch("more than one constraint named '\(constraint.name)'")
            }
            let context = ConstraintContext(
                constraint: constraint, sketch: sketch, indices: indices, parameters: parameters)
            constraints.append(try context.compile(moving: &entities))
        }
        return SolverSketch(entities: entities, constraints: constraints)
    }

    static func entities(_ solution: SolverSolution, of sketch: SketchFeature) -> [SketchEntity] {
        zip(sketch.entities, solution.entities).map { entity, solved in
            SketchEntity(name: entity.name, solved.geometry.document, construction: entity.construction)
        }
    }

    static func state(_ state: SolverState, of sketch: SketchFeature) -> SketchSolveState {
        func names(_ indices: [Int]) -> [String] {
            indices.map { sketch.constraints.indices.contains($0) ? sketch.constraints[$0].name : "#\($0)" }
        }
        return switch state {
        case .fullyConstrained: .fullyConstrained
        case .underConstrained(let dof): .underConstrained(dof: dof)
        case .overConstrained(let conflicting): .overConstrained(conflicting: names(conflicting))
        case .redundant(let redundant): .redundant(names(redundant))
        case .failed: .failed
        }
    }
}

private struct ConstraintContext {
    let constraint: SketchConstraint
    let sketch: SketchFeature
    let indices: [String: Int]
    let parameters: ParameterTable

    func fail(_ detail: String) -> FeatureError {
        .sketch("\(constraint.name) (\(constraint.kind.rawValue)): \(detail)")
    }

    func compile(moving entities: inout [SolverEntity]) throws(FeatureError) -> SolverConstraint {
        let shape = constraint.kind.shape
        guard constraint.points.count == shape.points else {
            throw fail("needs \(shape.points) point\(shape.points == 1 ? "" : "s"), got \(constraint.points.count)")
        }
        guard constraint.entities.count == shape.entities else {
            throw fail(
                "needs \(shape.entities) entit\(shape.entities == 1 ? "y" : "ies"), got \(constraint.entities.count)")
        }
        if shape.value, constraint.value == nil { throw fail("needs a value") }
        if !shape.value, constraint.value != nil { throw fail("takes no value") }
        if let at = constraint.at, constraint.kind != .fixed || at.count != 2 {
            throw fail("'at' is only for fixed, as [x, y]")
        }
        let p = try constraint.points.map { (name) throws(FeatureError) in try point(name) }
        let e = try constraint.entities.map { (name) throws(FeatureError) in try entity(name) }
        try checkKinds(entities: e, points: p)
        var value = try constraint.value.map { (scalar) throws(FeatureError) in try evaluate(scalar, "value") } ?? 0
        if constraint.kind.needsPositiveValue, !(value > 0) { throw fail("the value must be greater than 0") }
        if constraint.kind == .angle { value *= .pi / 180 }
        switch constraint.kind {
        case .coincident: return .coincident(p[0], p[1])
        case .horizontal: return .horizontal(e[0])
        case .vertical: return .vertical(e[0])
        case .parallel: return .parallel(e[0], e[1])
        case .perpendicular: return .perpendicular(e[0], e[1])
        case .tangent: return .tangent(e[0], e[1])
        case .tangentAt: return .tangentAt(p[0], p[1])
        case .equal: return .equal(e[0], e[1])
        case .distance: return .distance(p[0], p[1], value)
        case .pointLineDistance: return .pointLineDistance(p[0], line: e[0], value)
        case .angle: return .angle(e[0], e[1], value)
        case .radius: return .radius(e[0], value)
        case .diameter: return .diameter(e[0], value)
        case .pointOnLine: return .pointOnLine(p[0], line: e[0])
        case .pointOnCircle: return .pointOnCircle(p[0], curve: e[0])
        case .fixed:
            if let at = constraint.at {
                let target = SIMD2(try evaluate(at[0], "at[0]"), try evaluate(at[1], "at[1]"))
                entities[p[0].entity].geometry.move(p[0], to: target)
            }
            return .fixed(p[0])
        }
    }

    /// The entity kinds and points each constraint accepts, checked here so tools can refuse before writing.
    func checkKinds(entities e: [Int], points p: [SolverPointRef]) throws(FeatureError) {
        if e.count == 2, e[0] == e[1] { throw fail("needs two different entities") }
        if p.count == 2, p[0] == p[1] { throw fail("needs two different points") }
        func geometry(_ index: Int) -> SketchEntityGeometry { sketch.entities[index].geometry }
        func isLine(_ index: Int) -> Bool { if case .line = geometry(index) { true } else { false } }
        func isCurve(_ index: Int) -> Bool {
            switch geometry(index) {
            case .arc, .circle: true
            case .line, .point: false
            }
        }
        func describe(_ index: Int) -> String { "\(sketch.entities[index].name) is a \(geometry(index).typeName)" }
        switch constraint.kind {
        case .horizontal, .vertical, .parallel, .perpendicular, .angle:
            if let bad = e.first(where: { !isLine($0) }) { throw fail("\(describe(bad)); it needs a line") }
        case .pointLineDistance, .pointOnLine:
            if !isLine(e[0]) { throw fail("\(describe(e[0])); it needs a line") }
        case .radius, .diameter, .pointOnCircle:
            if !isCurve(e[0]) { throw fail("\(describe(e[0])); it needs an arc or a circle") }
        case .tangent:
            guard e.allSatisfy({ isLine($0) || isCurve($0) }), !(isLine(e[0]) && isLine(e[1])) else {
                throw fail("it needs a line and an arc or circle, or two arcs or circles, not two lines or points")
            }
        case .equal:
            guard (isLine(e[0]) && isLine(e[1])) || (isCurve(e[0]) && isCurve(e[1])) else {
                throw fail("it needs two lines or two arcs or circles")
            }
        case .tangentAt:
            for ref in p {
                if case .start = ref { continue }
                if case .end = ref { continue }
                throw fail("it joins the ends of lines or arcs, such as line1.end and arc1.start")
            }
        case .coincident, .distance, .fixed:
            break
        }
    }

    func evaluate(_ scalar: Scalar, _ field: String) throws(FeatureError) -> Double {
        do {
            return try parameters.evaluate(scalar)
        } catch {
            throw fail("\(field) \(scalar): \(error)")
        }
    }

    func entity(_ name: String) throws(FeatureError) -> Int {
        guard let index = indices[name] else {
            let known = sketch.entities.map(\.name).joined(separator: ", ")
            throw fail("no entity named '\(name)'; entities: \(known.isEmpty ? "none" : known)")
        }
        return index
    }

    func point(_ name: String) throws(FeatureError) -> SolverPointRef {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        let index = try entity(parts[0])
        let geometry = sketch.entities[index].geometry
        let roles: [String] =
            switch geometry {
            case .point: []
            case .line: ["start", "end"]
            case .circle: ["center"]
            case .arc: ["start", "end", "center"]
            }
        guard parts.count == 2 else {
            if case .point = geometry { return .point(index) }
            throw fail("'\(name)' is not a point; use \(roles.map { "\(parts[0]).\($0)" }.joined(separator: " or "))")
        }
        guard roles.contains(parts[1]) else {
            let options =
                roles.isEmpty ? "\(parts[0]) itself" : roles.map { "\(parts[0]).\($0)" }.joined(separator: ", ")
            throw fail("'\(name)' is not a point of \(parts[0]); use \(options)")
        }
        return switch parts[1] {
        case "start": .start(index)
        case "end": .end(index)
        default: .center(index)
        }
    }
}

extension SketchConstraintKind {
    var shape: (points: Int, entities: Int, value: Bool) {
        switch self {
        case .coincident, .tangentAt: (2, 0, false)
        case .horizontal, .vertical: (0, 1, false)
        case .parallel, .perpendicular, .tangent, .equal: (0, 2, false)
        case .distance: (2, 0, true)
        case .pointLineDistance: (1, 1, true)
        case .angle: (0, 2, true)
        case .radius, .diameter: (0, 1, true)
        case .fixed: (1, 0, false)
        case .pointOnLine, .pointOnCircle: (1, 1, false)
        }
    }
}

extension SketchConstraintKind {
    var needsPositiveValue: Bool {
        switch self {
        case .distance, .pointLineDistance, .radius, .diameter: true
        default: false
        }
    }
}

extension SketchEntityGeometry {
    /// Why the solver could not use this entity, if it cannot.
    var problem: String? {
        switch self {
        case .point:
            return nil
        case .line(let start, let end):
            return start == end ? "the line has no length" : nil
        case .circle(_, let radius):
            return radius > 0 ? nil : "the radius must be greater than 0"
        case .arc(_, let radius, let start, let end):
            guard radius > 0 else { return "the radius must be greater than 0" }
            let span = (end - start).truncatingRemainder(dividingBy: 360)
            return span == 0 ? "the arc spans no angle or a full turn; use a circle for a full turn" : nil
        }
    }
}

extension SolverPointRef {
    var entity: Int {
        switch self {
        case .point(let index), .start(let index), .end(let index), .center(let index): index
        }
    }
}

extension SolverGeometry {
    /// Moves the guess so the referenced point sits at `target`; an arc end keeps its centre.
    mutating func move(_ ref: SolverPointRef, to target: SIMD2<Double>) {
        switch (self, ref) {
        case (.point, _): self = .point(target)
        case (.line(_, let end), .start): self = .line(target, end)
        case (.line(let start, _), .end): self = .line(start, target)
        case (.circle(_, let radius), _): self = .circle(center: target, radius: radius)
        case (.arc(_, let radius, let start, let end), .center):
            self = .arc(center: target, radius: radius, startAngle: start, endAngle: end)
        case (.arc(let center, _, _, let end), .start):
            let d = target - center
            self = .arc(
                center: center, radius: max((d * d).sum().squareRoot(), 1e-6), startAngle: atan2(d.y, d.x),
                endAngle: end)
        case (.arc(let center, _, let start, _), .end):
            let d = target - center
            self = .arc(
                center: center, radius: max((d * d).sum().squareRoot(), 1e-6), startAngle: start,
                endAngle: atan2(d.y, d.x))
        default: break
        }
    }

    private static func polar(_ d: SIMD2<Double>) -> (radius: Double, angle: Double) {
        (max((d * d).sum().squareRoot(), 1e-6), atan2(d.y, d.x))
    }
}

extension SketchEntityGeometry {
    var solver: SolverGeometry {
        let radians = Double.pi / 180
        return switch self {
        case .point(let p): .point(p.simd)
        case .line(let start, let end): .line(start.simd, end.simd)
        case .circle(let center, let radius): .circle(center: center.simd, radius: radius)
        case .arc(let center, let radius, let start, let end):
            .arc(center: center.simd, radius: radius, startAngle: start * radians, endAngle: end * radians)
        }
    }
}

extension SolverGeometry {
    var document: SketchEntityGeometry {
        func point(_ p: SIMD2<Double>) -> SketchPoint2 { SketchPoint2(p.x, p.y) }
        let degrees = 180 / Double.pi
        return switch self {
        case .point(let p): .point(point(p))
        case .line(let start, let end): .line(start: point(start), end: point(end))
        case .circle(let center, let radius): .circle(center: point(center), radius: radius)
        case .arc(let center, let radius, let start, let end):
            .arc(center: point(center), radius: radius, startAngle: start * degrees, endAngle: end * degrees)
        }
    }
}
