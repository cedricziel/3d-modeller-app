import CADModel

/// Returns the input geometry unchanged, with the state it was given.
struct FakeSketchSolver: SketchSolving {
    var state: SolverState = .fullyConstrained

    func solve(_ sketch: SolverSketch) throws(SketchSolvingError) -> SolverSolution {
        SolverSolution(entities: sketch.entities, state: state, degreesOfFreedom: 0)
    }
}
