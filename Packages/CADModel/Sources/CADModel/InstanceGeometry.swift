import simd

/// An origin with three orthonormal axes, in assembly coordinates (mm).
public struct Frame: Sendable, Equatable {
    public var origin: SIMD3<Double>
    public var xAxis: SIMD3<Double>
    public var yAxis: SIMD3<Double>
    public var zAxis: SIMD3<Double>

    public init(origin: SIMD3<Double>, xAxis: SIMD3<Double>, yAxis: SIMD3<Double>, zAxis: SIMD3<Double>) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.zAxis = zAxis
    }
}

/// One face or edge of one of an instance's bodies; `index` follows that body's topology.
public struct InstanceElement: Sendable, Equatable {
    public let body: String
    public let kind: GeometryKind
    public let index: Int
    public let name: String

    public init(body: String, kind: GeometryKind, index: Int, name: String) {
        self.body = body
        self.kind = kind
        self.index = index
        self.name = name
    }
}

public extension InstanceResult {
    /// The instance with its bodies where the part builds them, so a filter such as `normal -Z` means the same
    /// face whatever the placement. Joints resolve their references on this.
    func unmoved(partBodies: [BodyResult]) -> InstanceResult {
        let own = bodies.compactMap { body in partBodies.first { $0.name == body.name } }
        return InstanceResult(
            id: id, name: name, part: part, status: status, transform: status == .ok ? .identity : nil, bodies: own,
            names: names, movedByJoints: false, appearance: appearance)
    }

    /// The one face or edge the reference picks among the instance's bodies, or in `body` alone.
    func element(
        _ reference: GeometryReference, _ kind: GeometryKind, body: String?, parameters: ParameterTable
    ) throws(ReferenceError) -> InstanceElement {
        if case let .failed(reason) = status {
            throw ReferenceError("\(name) did not build: \(reason)")
        }
        var candidates = bodies
        if let body {
            candidates = bodies.filter { $0.name == body }
            guard !candidates.isEmpty else {
                let names = bodies.map(\.name).joined(separator: ", ")
                throw ReferenceError("\(name) has no body named \(body); bodies: \(names)")
            }
        }
        var found: [(body: BodyResult, topology: BodyTopology, matches: [Int])] = []
        var errors: [String] = []
        for candidate in candidates {
            guard let topology = candidate.topology else {
                errors.append("\(candidate.name) has no faces: \(candidate.error ?? "the kernel did not describe it")")
                continue
            }
            do {
                let matches = try GeometryResolver.resolve(
                    [reference], kind: kind, in: topology, parameters: parameters, names: names(of: candidate.name)
                )
                found.append((candidate, topology, matches))
            } catch {
                errors.append(candidates.count == 1 ? error.description : "\(candidate.name): \(error.description)")
            }
        }
        guard !found.isEmpty else { throw ReferenceError(errors.joined(separator: " ")) }
        guard found.count == 1 else {
            let owners = found.map(\.body.name).joined(separator: " and ")
            throw ReferenceError("'\(reference.text)' matches \(kind.rawValue) in \(owners) of \(name); add 'body'")
        }
        let (owner, topology, matches) = found[0]
        let names = (names(of: owner.name) ?? TopologyNames(topology)).names(kind)
        guard matches.count == 1 else {
            let shown = matches.prefix(10).map { names[$0] }.joined(separator: ", ")
            throw ReferenceError(
                "'\(reference.text)' matches \(matches.count) \(kind.rawValue) of \(name)/\(owner.name): \(shown)"
            )
        }
        return InstanceElement(body: owner.name, kind: kind, index: matches[0], name: names[matches[0]])
    }

    /// A frame on a face of the instance, refined by an edge of the same body; see `GeometryFrame`.
    func frame(
        face: GeometryReference, edge: GeometryReference?, body: String?, parameters: ParameterTable
    ) throws(ReferenceError) -> Frame {
        let faceElement = try element(face, .faces, body: body, parameters: parameters)
        let edgeElement = try edge.map { edge throws(ReferenceError) in
            try element(edge, .edges, body: faceElement.body, parameters: parameters)
        }
        guard let topology = bodies.first(where: { $0.name == faceElement.body })?.topology else {
            throw ReferenceError("\(name)/\(faceElement.body) has no faces")
        }
        return try GeometryFrame.frame(
            face: topology.faces[faceElement.index], edge: edgeElement.map { topology.edges[$0.index] }
        )
    }
}

public enum GeometryFrame {
    /// z is the planar face's outward normal or the axis of a cylinder, cone or torus. The origin is the edge's
    /// centre (circle) or midpoint, else the planar face's centroid or the centroid projected onto the axis. x runs
    /// along a straight edge, else along the first global axis that is not close to z.
    public static func frame(face: FaceDescriptor, edge: EdgeDescriptor?) throws(ReferenceError) -> Frame {
        let z: SIMD3<Double>
        var origin: SIMD3<Double>
        switch face.surface {
        case .plane:
            guard let normal = face.normal, simd_length(normal) > 0 else {
                throw ReferenceError("\(face.names.first ?? "the face") has no normal")
            }
            z = simd_normalize(normal)
            origin = face.centroid
        case .cylinder, .cone, .torus:
            guard let axis = face.axis, simd_length(axis) > 0, let axisOrigin = face.axisOrigin else {
                throw ReferenceError("\(face.names.first ?? "the face") has no axis")
            }
            z = simd_normalize(axis)
            origin = axisOrigin + simd_dot(face.centroid - axisOrigin, z) * z
        case .sphere, .other:
            throw ReferenceError(
                "\(face.names.first ?? "the face") is a \(face.surface.rawValue) face, which has no single direction; "
                    + "use a planar, cylindrical, conical or toroidal face"
            )
        }
        var x: SIMD3<Double>?
        if let edge {
            origin = edge.curve == .circle ? (edge.center ?? edge.midpoint) : edge.midpoint
            if edge.curve == .line, let direction = edge.direction {
                x = perpendicular(direction, to: z, minimum: 1e-9)
            }
        }
        let axes: [SIMD3<Double>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        let xAxis = x ?? axes.lazy.compactMap { perpendicular($0, to: z, minimum: 0.1) }.first ?? SIMD3(1, 0, 0)
        return Frame(origin: origin, xAxis: xAxis, yAxis: simd_cross(z, xAxis), zAxis: z)
    }

    private static func perpendicular(_ v: SIMD3<Double>, to z: SIMD3<Double>, minimum: Double) -> SIMD3<Double>? {
        let projected = v - simd_dot(v, z) * z
        return simd_length(projected) > minimum ? simd_normalize(projected) : nil
    }
}
