struct PartBuilder<Kernel: GeometryKernel> {
    private enum Unavailable {
        case brokenBy(String)
        case consumedBy(String)
    }

    private enum Stop: Error {
        case failed(FeatureError)
        case skipped(dependsOn: String)
    }

    let kernel: Kernel
    let parameters: ParameterTable
    private var bodies: [(name: String, body: Kernel.Body)] = []
    private var unavailable: [String: Unavailable] = [:]
    private var names: Set<String> = []
    private var newBodyCount = 0

    init(kernel: Kernel, parameters: ParameterTable) {
        self.kernel = kernel
        self.parameters = parameters
    }

    mutating func apply(_ feature: Feature) -> FeatureResult {
        var newBody: String?
        if feature.kind.createsNewBody {
            newBodyCount += 1
            newBody = "Body\(newBodyCount)"
        }
        let status: FeatureStatus
        if !names.insert(feature.name).inserted {
            status = .failed(.duplicateName(feature.name))
        } else if feature.suppressed {
            status = .suppressed
        } else {
            do throws(Stop) {
                try build(feature, newBody: newBody)
                status = .ok
            } catch {
                switch error {
                case .failed(let error): status = .failed(error)
                case .skipped(let dependency): status = .skipped(dependsOn: dependency)
                }
            }
        }
        if let newBody, status != .ok {
            if case .skipped(let root) = status {
                unavailable[newBody] = .brokenBy(root)
            } else {
                unavailable[newBody] = .brokenBy(feature.name)
            }
        }
        return FeatureResult(
            id: feature.id, name: feature.name, status: status, body: feature.kind.affectedBody(newBody: newBody))
    }

    var builtBodies: [(name: String, body: Kernel.Body)] { bodies }

    func bodyResults() throws -> [BodyResult] {
        var results: [BodyResult] = []
        for (name, body) in bodies {
            try Task.checkCancellation()
            var problems: [String] = []
            let metrics: BodyMetrics?
            do { metrics = try kernel.metrics(of: body) } catch {
                metrics = nil
                problems.append(String(describing: error))
            }
            let mesh: BodyMesh?
            do { mesh = try kernel.mesh(of: body) } catch {
                mesh = nil
                problems.append(String(describing: error))
            }
            results.append(
                BodyResult(
                    name: name, metrics: metrics, mesh: mesh,
                    error: problems.isEmpty ? nil : problems.joined(separator: "; ")))
        }
        return results
    }

    private mutating func build(_ feature: Feature, newBody: String?) throws(Stop) {
        switch feature.kind {
        case .primitive(let primitive):
            var target: Kernel.Body?
            if let name = primitive.operation.targetBody { target = try body(named: name) }
            let solid = try make(primitive.shape, primitive.placement)
            if let name = primitive.operation.targetBody, let target,
                let operation = primitive.operation.booleanOperation
            {
                let combined = try kernelCall { try kernel.boolean(operation, target, solid) }
                store(combined, as: name)
            } else if let newBody {
                store(solid, as: newBody)
            }
        case .boolean(let boolean):
            guard !boolean.tools.isEmpty else { throw .failed(.invalidTools("a boolean needs at least one tool body")) }
            guard !boolean.tools.contains(boolean.target) else {
                throw .failed(.invalidTools("\(boolean.target) cannot be a tool of itself"))
            }
            guard Set(boolean.tools).count == boolean.tools.count else {
                throw .failed(.invalidTools("a tool body is listed more than once"))
            }
            var result = try body(named: boolean.target)
            var tools: [Kernel.Body] = []
            for name in boolean.tools { tools.append(try body(named: name)) }
            for tool in tools {
                let current = result
                result = try kernelCall { try kernel.boolean(boolean.operation, current, tool) }
            }
            store(result, as: boolean.target)
            for name in boolean.tools {
                bodies.removeAll { $0.name == name }
                unavailable[name] = .consumedBy(feature.name)
            }
        case .transform(let transform):
            let original = try body(named: transform.body)
            let placement = try resolve(transform.placement)
            store(try kernelCall { try kernel.transform(original, by: placement) }, as: transform.body)
        }
    }

    private func body(named name: String) throws(Stop) -> Kernel.Body {
        if let entry = bodies.first(where: { $0.name == name }) { return entry.body }
        switch unavailable[name] {
        case .brokenBy(let feature)?: throw .skipped(dependsOn: feature)
        case .consumedBy(let feature)?: throw .failed(.bodyConsumed(name, by: feature))
        case nil: throw .failed(.unknownBody(name))
        }
    }

    private mutating func store(_ body: Kernel.Body, as name: String) {
        if let index = bodies.firstIndex(where: { $0.name == name }) {
            bodies[index].body = body
        } else {
            bodies.append((name, body))
        }
    }

    private func make(_ shape: PrimitiveShape, _ placement: Placement) throws(Stop) -> Kernel.Body {
        switch shape {
        case .box(let width, let depth, let height):
            let (w, d, h) = (try value(width, "width"), try value(depth, "depth"), try value(height, "height"))
            let p = try resolve(placement)
            return try kernelCall { try kernel.box(width: w, depth: d, height: h, placement: p) }
        case .cylinder(let radius, let height):
            let (r, h) = (try value(radius, "radius"), try value(height, "height"))
            let p = try resolve(placement)
            return try kernelCall { try kernel.cylinder(radius: r, height: h, placement: p) }
        case .sphere(let radius):
            let r = try value(radius, "radius")
            let p = try resolve(placement)
            return try kernelCall { try kernel.sphere(radius: r, placement: p) }
        case .cone(let bottomRadius, let topRadius, let height):
            let (b, t, h) = (
                try value(bottomRadius, "bottomRadius"), try value(topRadius, "topRadius"), try value(height, "height")
            )
            let p = try resolve(placement)
            return try kernelCall { try kernel.cone(bottomRadius: b, topRadius: t, height: h, placement: p) }
        case .torus(let majorRadius, let minorRadius):
            let (major, minor) = (try value(majorRadius, "majorRadius"), try value(minorRadius, "minorRadius"))
            let p = try resolve(placement)
            return try kernelCall { try kernel.torus(majorRadius: major, minorRadius: minor, placement: p) }
        }
    }

    private func resolve(_ placement: Placement) throws(Stop) -> ResolvedPlacement {
        ResolvedPlacement(
            translation: try vector(placement.translation, "placement.translation"),
            rotationAxis: try vector(placement.rotationAxis, "placement.rotationAxis"),
            rotationDegrees: try value(placement.rotationDegrees, "placement.rotationDegrees")
        )
    }

    private func vector(_ vector: Vector3, _ field: String) throws(Stop) -> SIMD3<Double> {
        SIMD3(try value(vector.x, "\(field).x"), try value(vector.y, "\(field).y"), try value(vector.z, "\(field).z"))
    }

    private func value(_ scalar: Scalar, _ field: String) throws(Stop) -> Double {
        do {
            return try parameters.evaluate(scalar)
        } catch {
            throw .failed(.expression(field: field, error))
        }
    }

    private func kernelCall<T>(_ operation: () throws -> T) throws(Stop) -> T {
        do {
            return try operation()
        } catch {
            throw .failed(.kernel(String(describing: error)))
        }
    }
}
