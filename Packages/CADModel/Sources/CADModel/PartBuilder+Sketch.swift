import Foundation
import simd

extension PartBuilder {
    mutating func buildSketch(_ sketch: SketchFeature, feature: Feature) throws(Stop) {
        let offset = try value(sketch.plane.offset, "plane.offset")
        let frame: SketchFrame
        switch sketch.plane {
        case .base(let base, _):
            frame = .base(base, offset: offset)
        case .face(let bodyName, let reference, _):
            let body = try body(named: bodyName)
            let topology = try kernelCall { try kernel.topology(of: body) }
            let face = try single(reference, .faces, in: topology, role: "the sketch plane")
            guard let planar = SketchFrame.face(topology.faces[face], offset: offset) else {
                throw .failed(.sketch("the sketch plane must be a planar face; \(reference) is not planar"))
            }
            frame = planar
        }
        let system: SolverSketch
        do throws(FeatureError) {
            system = try SketchCompiler.compile(sketch, parameters: parameters)
        } catch {
            throw .failed(error)
        }
        guard let sketchSolver else { throw .failed(.sketch("no sketch solver is available")) }
        let solution: SolverSolution
        do throws(SketchSolvingError) {
            solution = try sketchSolver.solve(system)
        } catch {
            throw .failed(.sketch(Self.describe(error, of: sketch)))
        }
        let entities = SketchCompiler.entities(solution, of: sketch)
        let result = SketchResult(
            id: feature.id, name: feature.name, frame: frame, entities: entities,
            state: SketchCompiler.state(solution.state, of: sketch), degreesOfFreedom: solution.degreesOfFreedom,
            profiles: SketchProfiles(entities))
        sketchResults.append(result)
        guard result.state.isUsable else { throw .failed(.sketch(result.state.description)) }
        sketches[feature.name] = result
    }

    mutating func buildExtrude(_ extrude: ExtrudeFeature, newBody: String?, feature: String) throws(Stop) {
        let sketch = try sketch(named: extrude.sketch)
        let profile = try profile(of: sketch, selecting: extrude.regions)
        let target = try extrude.operation.targetBody.map { (name) throws(Stop) in try body(named: name) }
        let (from, to) = try offsets(extrude, frame: sketch.frame, target: target)
        let solid = try kernelCall { try kernel.extrude(profile, from: from, to: to, feature: feature) }
        try combine(solid, into: target, extrude.operation, newBody: newBody, feature: feature)
    }

    mutating func buildRevolve(_ revolve: RevolveFeature, newBody: String?, feature: String) throws(Stop) {
        let sketch = try sketch(named: revolve.sketch)
        let profile = try profile(of: sketch, selecting: revolve.regions)
        let target = try revolve.operation.targetBody.map { (name) throws(Stop) in try body(named: name) }
        let (origin, direction) = try axis(revolve.axis, sketch: sketch)
        let angle = try value(revolve.angle, "angle")
        guard angle > 0, angle <= 360 else { throw .failed(.extent("the angle must be more than 0 and at most 360")) }
        let solid = try kernelCall {
            try kernel.revolve(
                profile, axisOrigin: origin, axisDirection: direction, angleDegrees: angle, feature: feature)
        }
        try combine(solid, into: target, revolve.operation, newBody: newBody, feature: feature)
    }

    private func sketch(named name: String) throws(Stop) -> SketchResult {
        if let sketch = sketches[name] { return sketch }
        if let root = unavailableSketches[name] { throw .skipped(dependsOn: root) }
        throw .failed(.sketch("no sketch named '\(name)' comes before this feature"))
    }

    private func profile(of sketch: SketchResult, selecting regions: [String]) throws(Stop) -> SketchProfile {
        do throws(FeatureError) {
            let regions = try sketch.profiles.regions(selecting: regions).map { region in
                SketchRegion(
                    outer: Self.qualified(region.outer, sketch.name),
                    holes: region.holes.map { Self.qualified($0, sketch.name) })
            }
            return SketchProfile(frame: sketch.frame, regions: regions)
        } catch {
            throw .failed(.sketch("\(sketch.name): \(error)"))
        }
    }

    private static func qualified(_ curves: [SketchCurve], _ sketch: String) -> [SketchCurve] {
        curves.map { SketchCurve(entity: "\(sketch).\($0.entity)", geometry: $0.geometry) }
    }

    private func offsets(_ extrude: ExtrudeFeature, frame: SketchFrame, target: Kernel.Body?) throws(Stop)
        -> (Double, Double)
    {
        switch extrude.extent {
        case .distance(let scalar):
            let distance = try value(scalar, "extent.value")
            guard distance > 0 else {
                throw .failed(.extent("the distance must be greater than 0; set reversed to go the other way"))
            }
            return (0, extrude.reversed ? -distance : distance)
        case .symmetric(let scalar):
            let distance = try value(scalar, "extent.value")
            guard distance > 0 else { throw .failed(.extent("the distance must be greater than 0")) }
            return (-distance / 2, distance / 2)
        case .throughAll:
            guard let target else { throw .failed(.extent("through all needs join, cut or intersect with a body")) }
            let bounds = try kernelCall { try kernel.bounds(of: .body(target)) }
            let heights = (0..<8).map { corner -> Double in
                let point = SIMD3(
                    corner & 1 == 0 ? bounds.min.x : bounds.max.x, corner & 2 == 0 ? bounds.min.y : bounds.max.y,
                    corner & 4 == 0 ? bounds.min.z : bounds.max.z)
                return simd_dot(point - frame.origin, frame.normal)
            }
            return (heights.min()! - 1, heights.max()! + 1)
        case .upToFace(let bodyName, let reference):
            let body = try body(named: bodyName)
            let topology = try kernelCall { try kernel.topology(of: body) }
            let face = topology.faces[try single(reference, .faces, in: topology, role: "the face to extrude up to")]
            guard face.surface == .plane, let normal = face.normal,
                abs(abs(simd_dot(simd_normalize(normal), frame.normal)) - 1) <= 1e-6
            else {
                throw .failed(.extent("\(reference) must be a planar face parallel to the sketch plane"))
            }
            let height = simd_dot(face.centroid - frame.origin, frame.normal)
            guard abs(height) > 1e-9 else { throw .failed(.extent("\(reference) lies in the sketch plane")) }
            return (0, height)
        }
    }

    private func axis(_ axis: RevolveAxis, sketch: SketchResult) throws(Stop) -> (SIMD3<Double>, SIMD3<Double>) {
        switch axis {
        case .x: return (.zero, SIMD3(1, 0, 0))
        case .y: return (.zero, SIMD3(0, 1, 0))
        case .z: return (.zero, SIMD3(0, 0, 1))
        case .sketchLine(let name):
            guard let entity = sketch.entities.first(where: { $0.name == name }),
                case .line(let start, let end) = entity.geometry
            else {
                throw .failed(.sketch("the axis \(name) is not a line of \(sketch.name)"))
            }
            let (a, b) = (sketch.frame.point(start.simd), sketch.frame.point(end.simd))
            guard simd_distance(a, b) > 1e-9 else { throw .failed(.sketch("the axis \(name) has no length")) }
            return (a, simd_normalize(b - a))
        case .edge(let bodyName, let reference):
            let body = try body(named: bodyName)
            let topology = try kernelCall { try kernel.topology(of: body) }
            let edge = topology.edges[try single(reference, .edges, in: topology, role: "the axis")]
            guard edge.curve == .line, simd_distance(edge.start, edge.end) > 1e-9 else {
                throw .failed(.reference("the axis \(reference) must be a straight edge"))
            }
            return (edge.start, simd_normalize(edge.end - edge.start))
        }
    }

    private func single(_ reference: GeometryReference, _ kind: GeometryKind, in topology: BodyTopology, role: String)
        throws(Stop) -> Int
    {
        let matches: [Int]
        do {
            matches = try GeometryResolver.resolve([reference], kind: kind, in: topology, parameters: parameters)
        } catch {
            throw .failed(.reference(error.description))
        }
        guard matches.count == 1 else {
            let names = TopologyNames(topology).names(kind)
            throw .failed(
                .reference(
                    "\(role) must be one \(kind.singular); \(reference) matches \(matches.count): "
                        + matches.map { names[$0] }.joined(separator: ", ")))
        }
        return matches[0]
    }

    private static func describe(_ error: SketchSolvingError, of sketch: SketchFeature) -> String {
        if let index = error.constraint, sketch.constraints.indices.contains(index) {
            return "\(sketch.constraints[index].name): \(error.reason)"
        }
        if let index = error.entity, sketch.entities.indices.contains(index) {
            return "\(sketch.entities[index].name): \(error.reason)"
        }
        return error.reason
    }
}
