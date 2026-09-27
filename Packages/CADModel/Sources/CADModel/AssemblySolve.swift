import Foundation
import simd

/// The assembly of one rebuild: every instance placed, the joints solved and the instances they move moved.
struct AssembledInstances<Body: Sendable> {
    let result: AssemblyResult
    /// Each ok instance's bodies in assembly coordinates, in assembly order.
    let bodies: [(instance: Instance, bodies: [(name: String, body: Body)])]
}

/// A joint that reaches the solver: its instances, its drive and its markers before the drive is folded in.
private struct SolvedJoint {
    let joint: Joint
    let sides: (InstanceResult, InstanceResult)
    let drive: JointDrive
    let markers: (a: RigidTransform, b: RigidTransform)
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
        var (joints, solved, freedoms) = solveJoints(
            assembly, instances: instances, partResults: partResults, solver: solver)
        var unmovable: [UUID: String] = [:]
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
                unmovable[id] = "\(entry.instance.name) could not be moved where the joints put it: \(error.reason)"
            }
        }
        if !unmovable.isEmpty {
            joints = zip(assembly.joints, joints).map { joint, result in
                guard result.status.holds,
                    let reason = unmovable[joint.a.instance] ?? unmovable[joint.b.instance]
                else { return result }
                return result.with(status: .failed(reason))
            }
        }
        let bodies = assembly.instances.compactMap { instance in
            placedBodies[instance.id].map { (instance, $0.placed.bodies) }
        }
        if !assembly.joints.isEmpty {
            instances = instances.map { instance in
                guard instance.status == .ok else { return instance }
                let grounded = assembly.instances.first { $0.id == instance.id }?.grounded ?? false
                if grounded { return instance.with(freedoms: 0) }
                guard let freedoms else { return instance }
                return instance.with(freedoms: freedoms[instance.id] ?? 6)
            }
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

    /// Each joint's status, the solved transform of every instance the joints moved, and the freedoms of every
    /// instance that reached the solver; no freedoms when nothing was solved.
    private func solveJoints(
        _ assembly: Assembly, instances: [InstanceResult], partResults: [UUID: [BodyResult]],
        solver: (any AssemblySolving)?
    ) -> ([JointResult], [UUID: RigidTransform], [UUID: Int]?) {
        guard !assembly.joints.isEmpty else { return ([], [:], nil) }
        let resolver = JointResolver(parameters: parameters, instances: instances, partBodies: partResults)
        var statuses: [UUID: JointStatus] = [:]
        var names: Set<String> = []
        var bodyIndex: [UUID: Int] = [:]
        var bodies: [SolverAssemblyBody] = []
        var solverJoints: [SolvedJoint] = []
        var markers: [SolverAssemblyJoint] = []
        let drives = Dictionary(
            assembly.joints.map { ($0.id, JointDrive.evaluate($0, parameters: parameters)) },
            uniquingKeysWith: { first, _ in first })
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
                let drive = drives[joint.id]!
                let driven = drive.driven(joint.kind, markerA: markerA)
                markers.append(
                    SolverAssemblyJoint(
                        kind: driven.kind, bodyA: index(of: a), markerA: driven.markerA, bodyB: index(of: b),
                        markerB: markerB))
                solverJoints.append(SolvedJoint(joint: joint, sides: (a, b), drive: drive, markers: (markerA, markerB)))
            } catch {
                statuses[joint.id] = .failed(error.reason)
            }
        }
        var solved: [UUID: RigidTransform] = [:]
        var values: [UUID: Double] = [:]
        var freedoms: [UUID: Int]?
        if !markers.isEmpty {
            let outcome = solve(
                SolverAssembly(bodies: bodies, joints: markers), solverJoints: solverJoints, assembly: assembly,
                solver: solver)
            for (position, entry) in solverJoints.enumerated() {
                var status = outcome.statuses[position]
                if let problem = entry.drive.problem { status = .failed(problem) }
                statuses[entry.joint.id] = status
                guard let placements = outcome.placements else { continue }
                let a = placements[markers[position].bodyA].composed(with: entry.markers.a)
                let b = placements[markers[position].bodyB].composed(with: entry.markers.b)
                values[entry.joint.id] =
                    entry.drive.isDriven && status.holds ? entry.drive.value : entry.drive.measure(a: a, b: b)
            }
            if let placements = outcome.placements {
                let mobility = Mobility.freedoms(
                    bodies: bodies.count, grounded: Set(bodies.indices.filter { bodies[$0].grounded }),
                    joints: markers.map {
                        MobilityJoint(
                            kind: $0.kind, bodyA: $0.bodyA, bodyB: $0.bodyB,
                            a: placements[$0.bodyA].composed(with: $0.markerA),
                            b: placements[$0.bodyB].composed(with: $0.markerB))
                    })
                freedoms = Dictionary(uniqueKeysWithValues: bodyIndex.map { ($0.key, mobility[$0.value]) })
            }
            for (id, index) in bodyIndex where !bodies[index].grounded {
                guard let placement = outcome.placements?[index], !placement.isClose(to: bodies[index].placement)
                else { continue }
                solved[id] = placement
            }
        }
        let results = assembly.joints.map { joint in
            let drive = drives[joint.id]!
            return JointResult(
                id: joint.id, name: joint.name, status: statuses[joint.id] ?? .failed("not solved"),
                motion: joint.kind.motion, value: values[joint.id], minimum: drive.minimum, maximum: drive.maximum,
                driven: drive.isDriven, freedoms: joint.kind.freedoms - (drive.isDriven ? 1 : 0))
        }
        return (results, solved, freedoms)
    }

    private func solve(
        _ system: SolverAssembly, solverJoints: [SolvedJoint],
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
        let explained = statuses.indices.map { index -> JointStatus in
            let joint = system.joints[index]
            guard case .failed(let reason) = statuses[index], system.bodies[joint.bodyA].grounded,
                system.bodies[joint.bodyB].grounded
            else { return statuses[index] }
            let (a, b) = solverJoints[index].sides
            return .failed("\(reason); \(a.name) and \(b.name) are both grounded, so neither can move")
        }
        return (explained, solution.placements)
    }

    private static func rounded(_ value: Double) -> String {
        Scalar.format((value * 10_000).rounded() / 10_000)
    }
}
