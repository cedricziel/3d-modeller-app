public enum SketchSolverError: Error, Sendable, Hashable {
    case invalidEntity(index: Int, reason: String)
    case invalidConstraint(index: Int, reason: String)
    case solverFailure(String)
}
