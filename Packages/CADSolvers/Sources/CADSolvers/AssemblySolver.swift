/// Solves rigid-body assemblies with FreeCAD's OndselSolver, as FreeCAD's Assembly workbench drives it.
public struct AssemblySolver: Sendable {
    public init() {}

    /// Places the bodies joined to grounded bodies so that every joint holds, judging each joint on the result.
    /// When the given placements leave a joint unsatisfied, it solves once more from placements where each joint's
    /// frames coincide, and keeps the better of the two.
    public func solve(_ system: AssemblySystem) throws(AssemblySolverError) -> AssemblySolution {
        try system.validate()
        let connected = Self.connectedToGround(system)
        let solvable = system.joints.indices.filter { index in
            let joint = system.joints[index]
            return connected.contains(joint.bodyA)
                && !(system.bodies[joint.bodyA].grounded && system.bodies[joint.bodyB].grounded)
        }
        let start = system.bodies.map(\.placement)
        guard !solvable.isEmpty else {
            return AssemblySolution(
                placements: start, joints: Self.judge(system, start, connected: connected, redundant: nil),
                failure: nil, attempts: 0)
        }
        let first = try attempt(system, from: start, connected: connected, solvable: solvable)
        guard first.failures > 0 else { return first.solution(attempts: 1) }
        let second = try attempt(
            system, from: Self.coincidentStart(system, start), connected: connected, solvable: solvable)
        return Self.better(first, second)
    }

    /// The attempt with fewer unsatisfied joints; on a tie, one that did not throw over one that did.
    static func better(_ first: Attempt, _ second: Attempt) -> AssemblySolution {
        let preferSecond =
            second.failures < first.failures
            || (second.failures == first.failures && first.failure != nil && second.failure == nil)
        return (preferSecond ? second : first).solution(attempts: 2)
    }

    struct Attempt {
        let placements: [RigidPlacement]
        let joints: [JointState]
        let failure: String?
        let failures: Int

        func solution(attempts: Int) -> AssemblySolution {
            AssemblySolution(placements: placements, joints: joints, failure: failure, attempts: attempts)
        }
    }

    private func attempt(
        _ system: AssemblySystem, from start: [RigidPlacement], connected: Set<Int>, solvable: [Int]
    ) throws(AssemblySolverError) -> Attempt {
        let bodies = system.bodies.indices.filter { connected.contains($0) }
        let local = Dictionary(uniqueKeysWithValues: bodies.enumerated().map { ($1, $0) })
        let ondsel = try OndselSystem()
        for body in bodies {
            try ondsel.addBody(start[body], grounded: system.bodies[body].grounded)
        }
        for index in solvable {
            let joint = system.joints[index]
            try ondsel.addJoint(joint.kind, local[joint.bodyA]!, joint.markerA, local[joint.bodyB]!, joint.markerB)
        }
        var placements = start
        var redundant: [Int: Bool] = [:]
        var failure: String?
        do {
            try ondsel.solve()
            for body in bodies { placements[body] = try ondsel.placement(ofBody: local[body]!) }
            for (position, index) in solvable.enumerated() {
                redundant[index] = try ondsel.report(ofJoint: position).redundant > 0
            }
        } catch {
            guard case .solverFailure(let message) = error else { throw error }
            placements = start
            failure = message
        }
        if placements.contains(where: { $0.problem != nil }) {
            placements = start
            failure = failure ?? "the solver returned a placement that is not rigid"
            redundant = [:]
        }
        let joints = Self.judge(system, placements, connected: connected, redundant: failure == nil ? redundant : nil)
        let failures = solvable.count { !joints[$0].holds }
        return Attempt(placements: placements, joints: joints, failure: failure, failures: failures)
    }

    private static func judge(
        _ system: AssemblySystem, _ placements: [RigidPlacement], connected: Set<Int>, redundant: [Int: Bool]?
    ) -> [JointState] {
        let anyRedundant = redundant?.values.contains(true) ?? false
        return system.joints.enumerated().map { index, joint in
            guard connected.contains(joint.bodyA) else { return .notConnected }
            let a = placements[joint.bodyA].composed(with: joint.markerA)
            let b = placements[joint.bodyB].composed(with: joint.markerB)
            let state = JointCheck.state(joint.kind, a, b)
            if state.holds { return redundant?[index] == true ? .redundant : .satisfied }
            return anyRedundant ? .conflicting : state
        }
    }

    /// The bodies joined, directly or through other bodies, to a grounded body.
    private static func connectedToGround(_ system: AssemblySystem) -> Set<Int> {
        var connected = Set(system.bodies.indices.filter { system.bodies[$0].grounded })
        var changed = true
        while changed {
            changed = false
            for joint in system.joints where connected.contains(joint.bodyA) != connected.contains(joint.bodyB) {
                connected.insert(joint.bodyA)
                connected.insert(joint.bodyB)
                changed = true
            }
        }
        return connected
    }

    /// Placements that put each joint's B frame exactly onto its A frame, spreading out from the grounded bodies.
    private static func coincidentStart(_ system: AssemblySystem, _ start: [RigidPlacement]) -> [RigidPlacement] {
        var placements = start
        var placed = Set(system.bodies.indices.filter { system.bodies[$0].grounded })
        var changed = true
        while changed {
            changed = false
            for joint in system.joints {
                switch (placed.contains(joint.bodyA), placed.contains(joint.bodyB)) {
                case (true, false):
                    placements[joint.bodyB] = placements[joint.bodyA].composed(with: joint.markerA)
                        .composed(with: joint.markerB.inverse)
                    placed.insert(joint.bodyB)
                    changed = true
                case (false, true):
                    placements[joint.bodyA] = placements[joint.bodyB].composed(with: joint.markerB)
                        .composed(with: joint.markerA.inverse)
                    placed.insert(joint.bodyA)
                    changed = true
                default:
                    break
                }
            }
        }
        return placements
    }
}
