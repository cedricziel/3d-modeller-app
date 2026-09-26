import CPlaneGCS

/// Solves sketches with FreeCAD's PlaneGCS. Each call builds its own system, so concurrent calls
/// are independent.
public struct SketchSolver: Sendable {
    public init() {}

    public func solve(_ sketch: Sketch) throws(SketchSolverError) -> SketchSolution {
        try sketch.validate()
        let system = try PlaneGCSSystem()
        for entity in sketch.entities {
            try system.add(entity.geometry)
        }
        for (index, constraint) in sketch.constraints.enumerated() {
            try system.add(constraint.shimValue, tag: index + 1)
        }
        let report = try system.solve()

        var entities = sketch.entities
        if report.solved {
            for index in entities.indices {
                entities[index].geometry = entities[index].geometry.replacing(try system.values(ofEntity: index))
            }
        }
        let finite = entities.allSatisfy { $0.geometry.problem == nil }
        let solved = report.solved && finite
        return SketchSolution(
            entities: solved ? entities : sketch.entities,
            state: state(report, solved: solved),
            degreesOfFreedom: report.dof
        )
    }

    private func state(_ report: PlaneGCSSystem.Report, solved: Bool) -> SketchState {
        if !report.conflictingTags.isEmpty {
            return .overConstrained(conflicting: report.conflictingTags.map { $0 - 1 })
        }
        if !solved { return .failed }
        if !report.redundantTags.isEmpty { return .redundant(report.redundantTags.map { $0 - 1 }) }
        return report.dof > 0 ? .underConstrained(dof: report.dof) : .fullyConstrained
    }
}

extension SketchGeometry {
    fileprivate func replacing(_ values: [Double]) -> SketchGeometry {
        switch (self, values.count) {
        case (.point, 2):
            .point(SketchPoint(values[0], values[1]))
        case (.line, 4):
            .line(start: SketchPoint(values[0], values[1]), end: SketchPoint(values[2], values[3]))
        case (.circle, 3):
            .circle(center: SketchPoint(values[0], values[1]), radius: values[2])
        case (.arc, 5):
            .arc(
                center: SketchPoint(values[0], values[1]), radius: values[2], startAngle: values[3], endAngle: values[4]
            )
        default:
            self
        }
    }
}

extension SketchPointRef {
    fileprivate var shimValue: PGSPointRef {
        switch self {
        case .point(let index): PGSPointRef(entity: Int32(index), role: Int32(PGS_ROLE_POINT))
        case .start(let index): PGSPointRef(entity: Int32(index), role: Int32(PGS_ROLE_START))
        case .end(let index): PGSPointRef(entity: Int32(index), role: Int32(PGS_ROLE_END))
        case .center(let index): PGSPointRef(entity: Int32(index), role: Int32(PGS_ROLE_CENTER))
        }
    }
}

extension SketchConstraint {
    fileprivate var shimValue: PGSConstraint {
        func make(
            _ kind: Int, first: Int = 0, second: Int = 0, p1: SketchPointRef? = nil, p2: SketchPointRef? = nil,
            value: Double = 0
        ) -> PGSConstraint {
            PGSConstraint(
                kind: Int32(kind), first: Int32(first), second: Int32(second),
                p1: p1?.shimValue ?? PGSPointRef(), p2: p2?.shimValue ?? PGSPointRef(), value: value
            )
        }
        return switch self {
        case .coincident(let p, let q): make(PGS_COINCIDENT, p1: p, p2: q)
        case .horizontal(let line): make(PGS_HORIZONTAL, first: line)
        case .vertical(let line): make(PGS_VERTICAL, first: line)
        case .parallel(let a, let b): make(PGS_PARALLEL, first: a, second: b)
        case .perpendicular(let a, let b): make(PGS_PERPENDICULAR, first: a, second: b)
        case .tangent(let a, let b): make(PGS_TANGENT, first: a, second: b)
        case .tangentAt(let p, let q): make(PGS_TANGENT_AT, p1: p, p2: q)
        case .equal(let a, let b): make(PGS_EQUAL, first: a, second: b)
        case .distance(let p, let q, let value): make(PGS_DISTANCE, p1: p, p2: q, value: value)
        case .pointLineDistance(let p, let line, let value):
            make(PGS_POINT_LINE_DISTANCE, first: line, p1: p, value: value)
        case .angle(let a, let b, let value): make(PGS_ANGLE, first: a, second: b, value: value)
        case .radius(let curve, let value): make(PGS_RADIUS, first: curve, value: value)
        case .diameter(let curve, let value): make(PGS_DIAMETER, first: curve, value: value)
        case .fixed(let p): make(PGS_FIXED, p1: p)
        case .pointOnLine(let p, let line): make(PGS_POINT_ON_LINE, first: line, p1: p)
        case .pointOnCircle(let p, let curve): make(PGS_POINT_ON_CIRCLE, first: curve, p1: p)
        }
    }
}
