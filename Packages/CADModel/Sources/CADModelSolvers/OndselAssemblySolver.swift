import CADModel
import CADSolvers

/// Solves assembly joints with FreeCAD's OndselSolver through `CADSolvers`.
public struct OndselAssemblySolver: AssemblySolving {
    private let solver = AssemblySolver()

    public init() {}

    public func solve(_ assembly: SolverAssembly) throws(AssemblySolvingError) -> SolverAssemblySolution {
        let system = AssemblySystem(
            bodies: assembly.bodies.map { AssemblyBody(placement: $0.placement.solver, grounded: $0.grounded) },
            joints: assembly.joints.map {
                AssemblyJoint($0.kind.solver, $0.bodyA, $0.markerA.solver, $0.bodyB, $0.markerB.solver)
            })
        let solution: AssemblySolution
        do {
            solution = try solver.solve(system)
        } catch {
            switch error {
            case .invalidBody(let index, let reason): throw AssemblySolvingError(body: index, reason: reason)
            case .invalidJoint(let index, let reason): throw AssemblySolvingError(joint: index, reason: reason)
            case .nothingGrounded: throw AssemblySolvingError(reason: "no body is grounded")
            case .solverFailure(let message): throw AssemblySolvingError(reason: "the solver failed: \(message)")
            }
        }
        return SolverAssemblySolution(
            placements: solution.placements.map { RigidTransform(rotation: $0.rotation, translation: $0.translation) },
            joints: solution.joints.map(\.model), failure: solution.failure)
    }
}

extension RigidTransform {
    fileprivate var solver: RigidPlacement { RigidPlacement(rotation: rotation, translation: translation) }
}

extension JointKind {
    fileprivate var solver: AssemblyJointKind {
        switch self {
        case .fixed: .fixed
        case .revolute: .revolute
        case .slider: .slider
        case .cylindrical: .cylindrical
        case .ball: .ball
        case .planar: .planar
        }
    }
}

extension JointState {
    fileprivate var model: SolverJointState {
        switch self {
        case .satisfied: .satisfied
        case .redundant: .redundant
        case .conflicting: .conflicting
        case .notConnected: .notConnected
        case .unsatisfied(let distance, let angle): .unsatisfied(distance: distance, angle: angle)
        }
    }
}
