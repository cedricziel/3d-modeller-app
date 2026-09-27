public enum JointState: Sendable, Hashable {
    case satisfied
    /// Satisfied, but OndselSolver set some of its constraints aside as implied by other joints.
    case redundant
    /// Not satisfied, while the solver set constraints aside: the joints contradict each other.
    case conflicting
    /// Its bodies are not joined to a grounded body, so it was not solved.
    case notConnected
    /// Not satisfied: the worst origin offset (mm) and the worst axis angle (radians).
    case unsatisfied(distance: Double, angle: Double)

    var holds: Bool { self == .satisfied || self == .redundant }
}

public struct AssemblySolution: Sendable, Hashable {
    /// Every body's placement after the solve, or as given when it was not solved.
    public let placements: [RigidPlacement]
    public let joints: [JointState]
    /// The solver's message when the attempt whose result this is threw.
    public let failure: String?
    /// How many solves ran: 0 without solvable joints, 2 when the first left a joint unsatisfied.
    public let attempts: Int

    public init(placements: [RigidPlacement], joints: [JointState], failure: String?, attempts: Int) {
        self.placements = placements
        self.joints = joints
        self.failure = failure
        self.attempts = attempts
    }
}

public enum AssemblySolverError: Error, Sendable, Hashable {
    case invalidBody(index: Int, reason: String)
    case invalidJoint(index: Int, reason: String)
    case nothingGrounded
    case solverFailure(String)
}
