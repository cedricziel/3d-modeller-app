import Foundation
import simd

/// The assembly of one rebuild: every instance placed, the joints solved and the instances they move moved.
struct AssembledInstances<Body: Sendable> {
    let result: AssemblyResult
    /// Each ok instance's bodies in assembly coordinates, in assembly order.
    let bodies: [(instance: Instance, bodies: [(name: String, body: Body)])]
}

extension AssemblyBuilder {
    func assemble(
        _ assembly: Assembly, partResults: [UUID: [BodyResult]], solver: (any AssemblySolving)?
    ) throws -> AssembledInstances<Kernel.Body> {
        var instances: [InstanceResult] = []
        var placedBodies: [UUID: (instance: Instance, placed: Placed)] = [:]
        for (instance, outcome) in try place(assembly) {
            let partBodies = partResults[instance.part] ?? []
            switch outcome {
            case .success(let placed):
                instances.append(result(instance, placed, partBodies))
                placedBodies[instance.id] = (instance, placed)
            case .failure(let failure):
                instances.append(
                    InstanceResult(
                        id: instance.id, name: instance.name, part: instance.part, status: .failed(failure.reason),
                        transform: nil, bodies: []))
            }
        }
        let (joints, solved) = solveJoints(assembly, instances: instances, partResults: partResults, solver: solver)
        for (id, transform) in solved {
            guard let index = instances.firstIndex(where: { $0.id == id }), let entry = placedBodies[id] else {
                continue
            }
            let partBodies = partResults[entry.instance.part] ?? []
            do throws(Failure) {
                let placed = try place(entry.instance, at: transform.resolvedPlacement)
                instances[index] = result(entry.instance, placed, partBodies, movedByJoints: true)
                placedBodies[id] = (entry.instance, placed)
            } catch {
                instances[index] = InstanceResult(
                    id: id, name: entry.instance.name, part: entry.instance.part, status: .failed(error.reason),
                    transform: nil, bodies: [])
                placedBodies[id] = nil
            }
        }
        let bodies = assembly.instances.compactMap { instance in
            placedBodies[instance.id].map { (instance, $0.placed.bodies) }
        }
        return AssembledInstances(result: AssemblyResult(instances: instances, joints: joints), bodies: bodies)
    }

    private func result(
        _ instance: Instance, _ placed: Placed, _ partBodies: [BodyResult], movedByJoints: Bool = false
    ) -> InstanceResult {
        InstanceResult(
            id: instance.id, name: instance.name, part: instance.part, status: .ok, transform: placed.transform,
            bodies: bodyResults(placed, partResults: partBodies), names: Self.names(placed, partResults: partBodies),
            movedByJoints: movedByJoints)
    }

    /// Each joint's status, and the solved transform of every instance the joints moved.
    private func solveJoints(
        _ assembly: Assembly, instances: [InstanceResult], partResults: [UUID: [BodyResult]],
        solver: (any AssemblySolving)?
    ) -> ([JointResult], [UUID: RigidTransform]) {
        guard !assembly.joints.isEmpty else { return ([], [:]) }
        let resolver = JointResolver(parameters: parameters, instances: instances, partBodies: partResults)
        var statuses: [UUID: JointStatus] = [:]
        var names: Set<String> = []
        var bodyIndex: [UUID: Int] = [:]
        var bodies: [SolverAssemblyBody] = []
        var solverJoints: [(joint: Joint, sides: (InstanceResult, InstanceResult))] = []
        var markers: [SolverAssemblyJoint] = []
        func index(of instance: InstanceResult) -> Int {
            if let existing = bodyIndex[instance.id] { return existing }
            let grounded = assembly.instances.first { $0.id == instance.id }?.grounded ?? false
            bodies.append(SolverAssemblyBody(placement: instance.transform ?? .identity, grounded: grounded))
            bodyIndex[instance.id] = bodies.count - 1
            return bodies.count - 1
        }
        for joint in assembly.joints {
            guard names.insert(joint.name).inserted else {
                statuses[joint.id] = .failed("another joint is already named '\(joint.name)'")
                continue
            }
            do throws(JointResolver.Failure) {
                let (a, markerA) = try resolver.marker(joint.a, "a", mate: false)
                let (b, markerB) = try resolver.marker(joint.b, "b", mate: !joint.flip)
                guard a.id != b.id else {
                    statuses[joint.id] = .failed("both sides are on \(a.name)")
                    continue
                }
                markers.append(
                    SolverAssemblyJoint(
                        kind: joint.kind, bodyA: index(of: a), markerA: markerA, bodyB: index(of: b), markerB: markerB))
                solverJoints.append((joint, (a, b)))
            } catch {
                statuses[joint.id] = .failed(error.reason)
            }
        }
        var solved: [UUID: RigidTransform] = [:]
        if !markers.isEmpty {
            let outcome = solve(
                SolverAssembly(bodies: bodies, joints: markers), solverJoints: solverJoints, assembly: assembly,
                solver: solver)
            for (position, entry) in solverJoints.enumerated() { statuses[entry.joint.id] = outcome.statuses[position] }
            for (id, index) in bodyIndex where !bodies[index].grounded {
                guard let placement = outcome.placements?[index], !placement.isClose(to: bodies[index].placement)
                else { continue }
                solved[id] = placement
            }
        }
        let results = assembly.joints.map { joint in
            JointResult(id: joint.id, name: joint.name, status: statuses[joint.id] ?? .failed("not solved"))
        }
        return (results, solved)
    }

    private func solve(
        _ system: SolverAssembly, solverJoints: [(joint: Joint, sides: (InstanceResult, InstanceResult))],
        assembly: Assembly, solver: (any AssemblySolving)?
    ) -> (statuses: [JointStatus], placements: [RigidTransform]?) {
        func all(_ reason: String) -> (statuses: [JointStatus], placements: [RigidTransform]?) {
            (Array(repeating: .failed(reason), count: system.joints.count), nil)
        }
        guard let solver else { return all("no assembly solver is available") }
        guard system.bodies.contains(where: \.grounded) else {
            guard assembly.instances.contains(where: \.grounded) else {
                return all("no instance is grounded; ground one with edit_instance")
            }
            return (
                solverJoints.map {
                    .failed("\($0.sides.0.name) and \($0.sides.1.name) are not connected to a grounded instance")
                },
                nil
            )
        }
        let solution: SolverAssemblySolution
        do {
            solution = try solver.solve(system)
        } catch {
            return all("the solver refused the assembly: \(error.reason)")
        }
        guard solution.placements.count == system.bodies.count, solution.joints.count == system.joints.count else {
            return all("the solver returned an incomplete solution")
        }
        let statuses = zip(solution.joints, solverJoints).map { state, entry -> JointStatus in
            switch state {
            case .satisfied: return .ok
            case .redundant: return .redundant
            case .conflicting: return .failed("conflicts with other joints")
            case .notConnected:
                return .failed(
                    "\(entry.sides.0.name) and \(entry.sides.1.name) are not connected to a grounded instance")
            case .unsatisfied(let distance, let angle):
                let reason =
                    "not satisfied: origins \(Self.rounded(distance)) mm apart, axes \(Self.rounded(angle * 180 / .pi))° apart"
                return .failed(solution.failure.map { "the solver failed (\($0)); \(reason)" } ?? reason)
            }
        }
        return (statuses, solution.placements)
    }

    private static func rounded(_ value: Double) -> String {
        Scalar.format((value * 10_000).rounded() / 10_000)
    }
}
