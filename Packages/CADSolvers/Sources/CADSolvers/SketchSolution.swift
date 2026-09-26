public enum SketchState: Sendable, Hashable {
    case fullyConstrained
    case underConstrained(dof: Int)
    /// Indices into `Sketch.constraints` of every constraint in a contradicting group.
    case overConstrained(conflicting: [Int])
    /// Indices into `Sketch.constraints` that PlaneGCS set aside as implied by the others. It is
    /// the set it chose to drop, not every constraint involved: of three identical distances it
    /// names one.
    case redundant([Int])
    /// The solver did not converge, without conflicting constraints to blame.
    case failed
}

public struct SketchSolution: Sendable, Hashable {
    /// The solved entities when the solver converged, else the input entities.
    public let entities: [SketchEntity]
    public let state: SketchState
    public let degreesOfFreedom: Int

    public init(entities: [SketchEntity], state: SketchState, degreesOfFreedom: Int) {
        self.entities = entities
        self.state = state
        self.degreesOfFreedom = degreesOfFreedom
    }
}
