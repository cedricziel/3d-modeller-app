public struct SketchSolver: Sendable {
    public init() {}

    public func solve(_ sketch: Sketch) throws(SketchSolverError) {
        try sketch.validate()
        throw .solverFailure("not implemented")
    }
}
