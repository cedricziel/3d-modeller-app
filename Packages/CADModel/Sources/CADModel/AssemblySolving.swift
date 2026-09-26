/// A rigid body for the assembly solver, at its starting placement in assembly coordinates.
public struct SolverAssemblyBody: Sendable, Equatable {
    public var placement: RigidTransform
    public var grounded: Bool

    public init(placement: RigidTransform, grounded: Bool) {
        self.placement = placement
        self.grounded = grounded
    }
}

/// A joint between marker frames given in each body's own coordinates.
public struct SolverAssemblyJoint: Sendable, Equatable {
    public var kind: JointKind
    public var bodyA: Int
    public var markerA: RigidTransform
    public var bodyB: Int
    public var markerB: RigidTransform

    public init(kind: JointKind, bodyA: Int, markerA: RigidTransform, bodyB: Int, markerB: RigidTransform) {
        self.kind = kind
        self.bodyA = bodyA
        self.markerA = markerA
        self.bodyB = bodyB
        self.markerB = markerB
    }
}

/// An assembly in a solver's terms: bodies and joints by index. At least one body is grounded.
public struct SolverAssembly: Sendable, Equatable {
    public var bodies: [SolverAssemblyBody]
    public var joints: [SolverAssemblyJoint]

    public init(bodies: [SolverAssemblyBody], joints: [SolverAssemblyJoint]) {
        self.bodies = bodies
        self.joints = joints
    }
}

public enum SolverJointState: Sendable, Equatable {
    case satisfied
    /// Satisfied, with constraints the solver found implied by other joints.
    case redundant
    /// Not satisfied because the joints contradict each other.
    case conflicting
    /// Not joined, through other joints, to a grounded body.
    case notConnected
    /// Not satisfied: the worst origin offset in mm and the worst axis angle in radians.
    case unsatisfied(distance: Double, angle: Double)
}

public struct SolverAssemblySolution: Sendable, Equatable {
    /// Every body's placement after the solve; the starting one when it was not solved.
    public var placements: [RigidTransform]
    public var joints: [SolverJointState]
    /// Why the solver gave up, when it did.
    public var failure: String?

    public init(placements: [RigidTransform], joints: [SolverJointState], failure: String?) {
        self.placements = placements
        self.joints = joints
        self.failure = failure
    }
}

/// An assembly the solver refused. `body` or `joint` is the index it blamed, if any.
public struct AssemblySolvingError: Error, Sendable, Equatable, CustomStringConvertible {
    public var body: Int?
    public var joint: Int?
    public var reason: String

    public init(body: Int? = nil, joint: Int? = nil, reason: String) {
        self.body = body
        self.joint = joint
        self.reason = reason
    }

    public var description: String { reason }
}

/// Solves the joints of an assembly; `CADModelSolvers` provides one backed by OndselSolver.
public protocol AssemblySolving: Sendable {
    func solve(_ assembly: SolverAssembly) throws(AssemblySolvingError) -> SolverAssemblySolution
}
