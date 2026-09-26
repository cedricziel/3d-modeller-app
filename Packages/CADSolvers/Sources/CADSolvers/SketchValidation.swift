enum EntityKind: String, Sendable {
    case point, line, circle, arc
}

extension SketchGeometry {
    var kind: EntityKind {
        switch self {
        case .point: .point
        case .line: .line
        case .circle: .circle
        case .arc: .arc
        }
    }

    var problem: String? {
        switch self {
        case .point(let point):
            return point.isFinite ? nil : "the point has a non-finite coordinate"
        case .line(let start, let end):
            guard start.isFinite, end.isFinite else { return "the line has a non-finite coordinate" }
            let length = ((end.x - start.x) * (end.x - start.x) + (end.y - start.y) * (end.y - start.y)).squareRoot()
            return length < 1e-9 ? "the line has zero length" : nil
        case .circle(let center, let radius):
            guard center.isFinite, radius.isFinite else { return "the circle has a non-finite value" }
            return radius > 0 ? nil : "the circle's radius must be greater than 0"
        case .arc(let center, let radius, let startAngle, let endAngle):
            guard center.isFinite, radius.isFinite, startAngle.isFinite, endAngle.isFinite else {
                return "the arc has a non-finite value"
            }
            if radius <= 0 { return "the arc's radius must be greater than 0" }
            return startAngle == endAngle ? "the arc spans no angle" : nil
        }
    }
}

extension SketchPoint {
    var isFinite: Bool { x.isFinite && y.isFinite }
}

extension SketchPointRef {
    var entity: Int {
        switch self {
        case .point(let index), .start(let index), .end(let index), .center(let index): index
        }
    }

    var isEndpoint: Bool {
        switch self {
        case .start, .end: true
        case .point, .center: false
        }
    }
}

extension Sketch {
    func validate() throws(SketchSolverError) {
        for (index, entity) in entities.enumerated() {
            if let reason = entity.geometry.problem {
                throw .invalidEntity(index: index, reason: reason)
            }
        }
        for (index, constraint) in constraints.enumerated() {
            if let reason = problem(with: constraint) {
                throw .invalidConstraint(index: index, reason: reason)
            }
        }
    }

    func kind(of index: Int) -> EntityKind { entities[index].geometry.kind }

    private func problem(with constraint: SketchConstraint) -> String? {
        switch constraint {
        case .coincident(let p, let q):
            return pointProblem(p) ?? pointProblem(q) ?? (p == q ? "a point cannot coincide with itself" : nil)
        case .horizontal(let line), .vertical(let line):
            return entityProblem(line, accepts: [.line])
        case .parallel(let a, let b), .perpendicular(let a, let b):
            return entityProblem(a, accepts: [.line]) ?? entityProblem(b, accepts: [.line]) ?? distinct(a, b)
        case .angle(let a, let b, let value):
            return entityProblem(a, accepts: [.line]) ?? entityProblem(b, accepts: [.line]) ?? distinct(a, b)
                ?? (value.isFinite ? nil : "the angle must be finite")
        case .tangent(let a, let b):
            if let problem = entityProblem(a, accepts: [.line, .circle, .arc])
                ?? entityProblem(b, accepts: [.line, .circle, .arc]) ?? distinct(a, b)
            {
                return problem
            }
            return kind(of: a) == .line && kind(of: b) == .line ? "two lines cannot be tangent" : nil
        case .tangentAt(let p, let q):
            if let problem = pointProblem(p) ?? pointProblem(q) { return problem }
            guard p.isEndpoint, q.isEndpoint else { return "tangentAt needs the start or end of a line or arc" }
            return p.entity == q.entity ? "tangentAt needs endpoints of two different entities" : nil
        case .equal(let a, let b):
            if let problem = entityProblem(a, accepts: [.line, .circle, .arc])
                ?? entityProblem(b, accepts: [.line, .circle, .arc]) ?? distinct(a, b)
            {
                return problem
            }
            return (kind(of: a) == .line) == (kind(of: b) == .line)
                ? nil : "equal needs two lines, or two circles or arcs"
        case .distance(let p, let q, let value):
            return pointProblem(p) ?? pointProblem(q) ?? (p == q ? "a distance needs two different points" : nil)
                ?? positive(value, "distance")
        case .pointLineDistance(let p, let line, let value):
            return pointProblem(p) ?? entityProblem(line, accepts: [.line]) ?? notOwnPoint(p, of: line)
                ?? positive(value, "distance")
        case .radius(let curve, let value):
            return entityProblem(curve, accepts: [.circle, .arc]) ?? positive(value, "radius")
        case .diameter(let curve, let value):
            return entityProblem(curve, accepts: [.circle, .arc]) ?? positive(value, "diameter")
        case .fixed(let p):
            return pointProblem(p)
        case .pointOnLine(let p, let line):
            return pointProblem(p) ?? entityProblem(line, accepts: [.line]) ?? notOwnPoint(p, of: line)
        case .pointOnCircle(let p, let curve):
            return pointProblem(p) ?? entityProblem(curve, accepts: [.circle, .arc]) ?? notOwnPoint(p, of: curve)
        }
    }

    private func entityProblem(_ index: Int, accepts kinds: Set<EntityKind>) -> String? {
        guard entities.indices.contains(index) else {
            return "entity \(index) does not exist; the sketch has \(entities.count) entities"
        }
        guard kinds.contains(kind(of: index)) else {
            let names = kinds.map(\.rawValue).sorted().joined(separator: " or ")
            return "entity \(index) is a \(kind(of: index).rawValue); this needs a \(names)"
        }
        return nil
    }

    private func pointProblem(_ ref: SketchPointRef) -> String? {
        let index = ref.entity
        guard entities.indices.contains(index) else {
            return "entity \(index) does not exist; the sketch has \(entities.count) entities"
        }
        let kind = kind(of: index)
        let valid =
            switch ref {
            case .point: kind == .point
            case .start, .end: kind == .line || kind == .arc
            case .center: kind == .circle || kind == .arc
            }
        return valid ? nil : "entity \(index) is a \(kind.rawValue) and has no \(ref.roleName) point"
    }

    private func distinct(_ a: Int, _ b: Int) -> String? {
        a == b ? "the constraint needs two different entities" : nil
    }

    private func notOwnPoint(_ ref: SketchPointRef, of entity: Int) -> String? {
        ref.entity == entity ? "the point belongs to entity \(entity) itself" : nil
    }

    private func positive(_ value: Double, _ name: String) -> String? {
        value.isFinite && value > 0 ? nil : "the \(name) must be a finite number greater than 0"
    }
}

extension SketchPointRef {
    fileprivate var roleName: String {
        switch self {
        case .point: "point"
        case .start: "start"
        case .end: "end"
        case .center: "center"
        }
    }
}
