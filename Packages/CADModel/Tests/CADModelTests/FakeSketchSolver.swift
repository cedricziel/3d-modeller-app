import CADModel

/// Returns the input geometry unchanged, with the state it was given.
struct FakeSketchSolver: SketchSolving {
    var state: SolverState = .fullyConstrained
    var degreesOfFreedom = 0

    func solve(_ sketch: SolverSketch) throws(SketchSolvingError) -> SolverSolution {
        SolverSolution(entities: sketch.entities, state: state, degreesOfFreedom: degreesOfFreedom)
    }
}
