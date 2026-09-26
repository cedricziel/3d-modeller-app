import Foundation

/// Places the assembly's instances by moving the bodies the parts already built.
struct AssemblyBuilder<Kernel: GeometryKernel> {
    struct Failure: Error {
        let reason: String
    }

    struct Placed {
        let transform: RigidTransform
        let bodies: [(name: String, body: Kernel.Body)]
    }

    let kernel: Kernel
    let parameters: ParameterTable
    let parts: [Part]
    /// The bodies each part built, by part id, in body order.
    let partBodies: [UUID: [(name: String, body: Kernel.Body)]]

    /// Every instance with its placed bodies or why it could not be placed, in assembly order.
    func place(_ assembly: Assembly) throws -> [(instance: Instance, outcome: Result<Placed, Failure>)] {
        var names: Set<String> = []
        var outcomes: [(instance: Instance, outcome: Result<Placed, Failure>)] = []
        for instance in assembly.instances {
            try Task.checkCancellation()
            guard names.insert(instance.name).inserted else {
                outcomes.append(
                    (instance, .failure(Failure(reason: "another instance is already named '\(instance.name)'"))))
                continue
            }
            do throws(Failure) {
                try outcomes.append((instance, .success(place(instance))))
            } catch {
                outcomes.append((instance, .failure(error)))
            }
        }
        return outcomes
    }

    private func place(_ instance: Instance) throws(Failure) -> Placed {
        guard let part = parts.first(where: { $0.id == instance.part }) else {
            throw Failure(reason: "its part no longer exists")
        }
        let placement = try resolve(instance.placement)
        let built = partBodies[part.id] ?? []
        guard !built.isEmpty else { throw Failure(reason: "part \(part.name) has no bodies") }
        var selected = built
        if let name = instance.body {
            selected = built.filter { $0.name == name }
            guard !selected.isEmpty else {
                let names = built.map(\.name).joined(separator: ", ")
                throw Failure(reason: "part \(part.name) has no body named \(name); bodies: \(names)")
            }
        }
        var moved: [(name: String, body: Kernel.Body)] = []
        for (name, body) in selected {
            do {
                try moved.append((name, kernel.transform(body, by: placement)))
            } catch {
                throw Failure(reason: "the kernel could not move \(name): \(error)")
            }
        }
        return Placed(transform: RigidTransform(placement), bodies: moved)
    }

    /// The part's body results moved into place, with metrics measured on the moved bodies.
    func bodyResults(_ placed: Placed, partResults: [BodyResult]) -> [BodyResult] {
        placed.bodies.map { name, body in
            let original = partResults.first { $0.name == name }
            var problems = original?.error.map { [$0] } ?? []
            let metrics: BodyMetrics?
            do { metrics = try kernel.metrics(of: body) } catch {
                metrics = nil
                problems.append(String(describing: error))
            }
            return BodyResult(
                name: name, metrics: metrics, mesh: original?.mesh?.transformed(by: placed.transform),
                topology: original?.topology?.transformed(by: placed.transform),
                error: problems.isEmpty ? nil : problems.joined(separator: "; ")
            )
        }
    }

    /// The part's names of each placed body, from its unmoved topology.
    static func names(_ placed: Placed, partResults: [BodyResult]) -> [String: TopologyNames] {
        var names: [String: TopologyNames] = [:]
        for (name, _) in placed.bodies {
            if let topology = partResults.first(where: { $0.name == name })?.topology {
                names[name] = TopologyNames(topology)
            }
        }
        return names
    }

    private func resolve(_ placement: Placement) throws(Failure) -> ResolvedPlacement {
        func value(_ scalar: Scalar, _ field: String) throws(Failure) -> Double {
            do {
                return try parameters.evaluate(scalar)
            } catch {
                throw Failure(reason: "placement.\(field): \(error)")
            }
        }
        func vector(_ vector: Vector3, _ field: String) throws(Failure) -> SIMD3<Double> {
            try SIMD3(
                value(vector.x, "\(field).x"), value(vector.y, "\(field).y"),
                value(vector.z, "\(field).z")
            )
        }
        return try ResolvedPlacement(
            translation: vector(placement.translation, "translation"),
            rotationAxis: vector(placement.rotationAxis, "rotationAxis"),
            rotationDegrees: value(placement.rotationDegrees, "rotationDegrees")
        )
    }
}
