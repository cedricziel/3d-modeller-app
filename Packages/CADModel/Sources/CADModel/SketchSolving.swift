/// A sketch in a solver's terms: entities and constraints by index, angles in radians.
public struct SolverSketch: Sendable, Hashable {
    public var entities: [SolverEntity]
    public var constraints: [SolverConstraint]

    public init(entities: [SolverEntity], constraints: [SolverConstraint]) {
        self.entities = entities
        self.constraints = constraints
    }
}

public struct SolverEntity: Sendable, Hashable {
    public var geometry: SolverGeometry
    public var construction: Bool

    public init(geometry: SolverGeometry, construction: Bool) {
        self.geometry = geometry
        self.construction = construction
    }
}

/// Angles are radians; an arc runs counter-clockwise from `startAngle` to `endAngle`.
public enum SolverGeometry: Sendable, Hashable {
    case point(SIMD2<Double>)
    case line(SIMD2<Double>, SIMD2<Double>)
    case circle(center: SIMD2<Double>, radius: Double)
    case arc(center: SIMD2<Double>, radius: Double, startAngle: Double, endAngle: Double)
}

public enum SolverPointRef: Sendable, Hashable {
    case point(Int), start(Int), end(Int), center(Int)
}

public enum SolverConstraint: Sendable, Hashable {
    case coincident(SolverPointRef, SolverPointRef)
    case horizontal(Int)
    case vertical(Int)
    case parallel(Int, Int)
    case perpendicular(Int, Int)
    case tangent(Int, Int)
    case tangentAt(SolverPointRef, SolverPointRef)
    case equal(Int, Int)
    case distance(SolverPointRef, SolverPointRef, Double)
    case pointLineDistance(SolverPointRef, line: Int, Double)
    case angle(Int, Int, Double)
    case radius(Int, Double)
    case diameter(Int, Double)
    case fixed(SolverPointRef)
    case pointOnLine(SolverPointRef, line: Int)
    case pointOnCircle(SolverPointRef, curve: Int)
}

/// Constraint indices refer to `SolverSketch.constraints`.
public enum SolverState: Sendable, Hashable {
    case fullyConstrained
    case underConstrained(dof: Int)
    case overConstrained(conflicting: [Int])
    case redundant([Int])
    case failed
}

public struct SolverSolution: Sendable, Hashable {
    /// The solved entities, or the input ones when the solve failed.
    public var entities: [SolverEntity]
    public var state: SolverState
    public var degreesOfFreedom: Int

    public init(entities: [SolverEntity], state: SolverState, degreesOfFreedom: Int) {
        self.entities = entities
        self.state = state
        self.degreesOfFreedom = degreesOfFreedom
    }
}

/// A sketch the solver refused. `constraint` or `entity` is the index it blamed, if any.
public struct SketchSolvingError: Error, Sendable, Equatable, CustomStringConvertible {
    public var constraint: Int?
    public var entity: Int?
    public var reason: String

    public init(constraint: Int? = nil, entity: Int? = nil, reason: String) {
        self.constraint = constraint
        self.entity = entity
        self.reason = reason
    }

    public var description: String { reason }
}

/// Solves 2D sketches; `CADModelSolvers` provides the PlaneGCS implementation.
public protocol SketchSolving: Sendable {
    func solve(_ sketch: SolverSketch) throws(SketchSolvingError) -> SolverSolution
}

/// A sketch's solve state in the document's terms, with constraints by name.
public enum SketchSolveState: Sendable, Equatable, CustomStringConvertible {
    case fullyConstrained
    case underConstrained(dof: Int)
    case overConstrained(conflicting: [String])
    case redundant([String])
    case failed

    public var description: String {
        switch self {
        case .fullyConstrained: "fully constrained"
        case .underConstrained(let dof): "under-constrained, \(dof) degree\(dof == 1 ? "" : "s") of freedom"
        case .overConstrained(let names): "over-constrained, \(names.joined(separator: ", ")) conflict"
        case .redundant(let names): "redundant: \(names.joined(separator: ", "))"
        case .failed: "solve failed"
        }
    }

    /// Whether the sketch can be used: over-constrained and failed sketches cannot.
    public var isUsable: Bool {
        switch self {
        case .fullyConstrained, .underConstrained, .redundant: true
        case .overConstrained, .failed: false
        }
    }
}
