import CADModel
import Synchronization

/// Records what it is asked to solve and answers with a scripted solution: by default every body stays and every
/// joint holds.
final class FakeAssemblySolver: AssemblySolving, Sendable {
    private let calls = Mutex<[SolverAssembly]>([])
    private let answer: @Sendable (SolverAssembly) -> SolverAssemblySolution

    init(answer: @escaping @Sendable (SolverAssembly) -> SolverAssemblySolution = FakeAssemblySolver.unchanged) {
        self.answer = answer
    }

    var received: [SolverAssembly] { calls.withLock { $0 } }

    func solve(_ assembly: SolverAssembly) throws(AssemblySolvingError) -> SolverAssemblySolution {
        calls.withLock { $0.append(assembly) }
        return answer(assembly)
    }

    @Sendable static func unchanged(_ assembly: SolverAssembly) -> SolverAssemblySolution {
        SolverAssemblySolution(
            placements: assembly.bodies.map(\.placement),
            joints: Array(repeating: .satisfied, count: assembly.joints.count), failure: nil)
    }
}
