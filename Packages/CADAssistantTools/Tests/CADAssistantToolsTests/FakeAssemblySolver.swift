import CADModel
import simd

/// Moves each body joined to a placed one so that the joint's frames coincide, starting from the grounded bodies,
/// and reports every joint satisfied.
struct FakeAssemblySolver: AssemblySolving {
    func solve(_ assembly: SolverAssembly) throws(AssemblySolvingError) -> SolverAssemblySolution {
        var placements = assembly.bodies.map(\.placement)
        var placed = Set(assembly.bodies.indices.filter { assembly.bodies[$0].grounded })
        var changed = true
        while changed {
            changed = false
            for joint in assembly.joints where placed.contains(joint.bodyA) && !placed.contains(joint.bodyB) {
                let target = placements[joint.bodyA].composed(with: joint.markerA)
                let inverse = RigidTransform(
                    rotation: joint.markerB.rotation.transpose,
                    translation: -(joint.markerB.rotation.transpose * joint.markerB.translation))
                placements[joint.bodyB] = target.composed(with: inverse)
                placed.insert(joint.bodyB)
                changed = true
            }
        }
        return SolverAssemblySolution(
            placements: placements, joints: Array(repeating: .satisfied, count: assembly.joints.count), failure: nil)
    }
}
