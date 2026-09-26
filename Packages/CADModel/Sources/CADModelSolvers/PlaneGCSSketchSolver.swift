import CADModel
import CADSolvers

/// Solves sketches with FreeCAD's PlaneGCS through `CADSolvers`.
public struct PlaneGCSSketchSolver: SketchSolving {
    private let solver = SketchSolver()

    public init() {}

    public func solve(_ sketch: SolverSketch) throws(SketchSolvingError) -> SolverSolution {
        let input = CADSolvers.Sketch(
            entities: sketch.entities.map(\.solver), constraints: sketch.constraints.map(\.solver))
        let solution: SketchSolution
        do {
            solution = try solver.solve(input)
        } catch {
            switch error {
            case .invalidEntity(let index, let reason): throw SketchSolvingError(entity: index, reason: reason)
            case .invalidConstraint(let index, let reason): throw SketchSolvingError(constraint: index, reason: reason)
            case .solverFailure(let message): throw SketchSolvingError(reason: "the solver failed: \(message)")
            }
        }
        let state: SolverState =
            switch solution.state {
            case .fullyConstrained: .fullyConstrained
            case .underConstrained(let dof): .underConstrained(dof: dof)
            case .overConstrained(let conflicting): .overConstrained(conflicting: conflicting)
            case .redundant(let redundant): .redundant(redundant)
            case .failed: .failed
            }
        return SolverSolution(
            entities: solution.entities.map(SolverEntity.init), state: state,
            degreesOfFreedom: solution.degreesOfFreedom)
    }
}

extension SolverEntity {
    var solver: CADSolvers.SketchEntity {
        let geometry: CADSolvers.SketchGeometry =
            switch self.geometry {
            case .point(let p): .point(SketchPoint(p.x, p.y))
            case .line(let a, let b): .line(start: SketchPoint(a.x, a.y), end: SketchPoint(b.x, b.y))
            case .circle(let center, let radius): .circle(center: SketchPoint(center.x, center.y), radius: radius)
            case .arc(let center, let radius, let start, let end):
                .arc(center: SketchPoint(center.x, center.y), radius: radius, startAngle: start, endAngle: end)
            }
        return CADSolvers.SketchEntity(geometry, construction: construction)
    }

    init(_ entity: CADSolvers.SketchEntity) {
        func simd(_ p: SketchPoint) -> SIMD2<Double> { SIMD2(p.x, p.y) }
        let geometry: SolverGeometry =
            switch entity.geometry {
            case .point(let p): .point(simd(p))
            case .line(let start, let end): .line(simd(start), simd(end))
            case .circle(let center, let radius): .circle(center: simd(center), radius: radius)
            case .arc(let center, let radius, let start, let end):
                .arc(center: simd(center), radius: radius, startAngle: start, endAngle: end)
            }
        self.init(geometry: geometry, construction: entity.construction)
    }
}

extension SolverPointRef {
    var solver: SketchPointRef {
        switch self {
        case .point(let index): .point(index)
        case .start(let index): .start(index)
        case .end(let index): .end(index)
        case .center(let index): .center(index)
        }
    }
}

extension SolverConstraint {
    var solver: CADSolvers.SketchConstraint {
        switch self {
        case .coincident(let p, let q): .coincident(p.solver, q.solver)
        case .horizontal(let line): .horizontal(line)
        case .vertical(let line): .vertical(line)
        case .parallel(let a, let b): .parallel(a, b)
        case .perpendicular(let a, let b): .perpendicular(a, b)
        case .tangent(let a, let b): .tangent(a, b)
        case .tangentAt(let p, let q): .tangentAt(p.solver, q.solver)
        case .equal(let a, let b): .equal(a, b)
        case .distance(let p, let q, let d): .distance(p.solver, q.solver, d)
        case .pointLineDistance(let p, let line, let d): .pointLineDistance(p.solver, line: line, d)
        case .angle(let a, let b, let angle): .angle(a, b, angle)
        case .radius(let curve, let r): .radius(curve, r)
        case .diameter(let curve, let d): .diameter(curve, d)
        case .fixed(let p): .fixed(p.solver)
        case .pointOnLine(let p, let line): .pointOnLine(p.solver, line: line)
        case .pointOnCircle(let p, let curve): .pointOnCircle(p.solver, curve: curve)
        }
    }
}
