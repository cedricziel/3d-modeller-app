import CADModel
import Foundation
import simd

struct FakeBody: Sendable {
    var volume: Double
    var boundsMin: SIMD3<Double>
    var boundsMax: SIMD3<Double>
    var topology = BodyTopology(faces: [], edges: [])
}

struct FakeKernelError: Error, CustomStringConvertible {
    let description: String
}

/// Boxes have exact volumes, bounds and named faces and edges; everything else is approximate but deterministic.
struct FakeKernel: GeometryKernel {
    var onBox: @Sendable () -> Void = {}
    var meshFails: @Sendable (FakeBody) -> Bool = { _ in false }
    var onMeasure: @Sendable () -> Void = {}

    private func positive(_ values: Double...) throws {
        guard values.allSatisfy({ $0 > 0 }) else { throw FakeKernelError(description: "dimensions must be positive") }
    }

    private func body(volume: Double, size: SIMD3<Double>, at placement: ResolvedPlacement) -> FakeBody {
        FakeBody(volume: volume, boundsMin: placement.translation, boundsMax: placement.translation + size)
    }

    func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement, feature: String) throws
        -> FakeBody
    {
        onBox()
        try positive(width, depth, height)
        var result = body(volume: width * depth * height, size: SIMD3(width, depth, height), at: placement)
        result.topology = .box(feature, origin: placement.translation, size: SIMD3(width, depth, height))
        return result
    }

    func cylinder(radius: Double, height: Double, placement: ResolvedPlacement, feature: String) throws -> FakeBody {
        try positive(radius, height)
        var result = body(
            volume: 3 * radius * radius * height, size: SIMD3(2 * radius, 2 * radius, height), at: placement)
        let centre = placement.translation + SIMD3(0, 0, height / 2)
        result.topology.faces = [
            FaceDescriptor(
                names: ["\(feature).side"], surface: .cylinder, centroid: centre, area: 2 * .pi * radius * height,
                axisOrigin: placement.translation, axis: SIMD3(0, 0, 1), radius: radius)
        ]
        return result
    }

    func sphere(radius: Double, placement: ResolvedPlacement, feature _: String) throws -> FakeBody {
        try positive(radius)
        return body(volume: 4 * radius * radius * radius, size: SIMD3(repeating: 2 * radius), at: placement)
    }

    func cone(
        bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement, feature _: String
    ) throws -> FakeBody {
        guard bottomRadius != topRadius else { throw FakeKernelError(description: "cone radii must differ") }
        return body(volume: height, size: SIMD3(1, 1, height), at: placement)
    }

    func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement, feature _: String) throws
        -> FakeBody
    {
        try positive(majorRadius, minorRadius)
        return body(volume: majorRadius * minorRadius, size: SIMD3(1, 1, 1), at: placement)
    }

    func boolean(_ operation: BooleanOperation, _ target: FakeBody, _ tool: FakeBody, feature _: String) throws
        -> FakeBody
    {
        var result = target
        result.topology = target.topology + tool.topology
        switch operation {
        case .union:
            result.volume += tool.volume
            result.boundsMin = pointwiseMin(target.boundsMin, tool.boundsMin)
            result.boundsMax = pointwiseMax(target.boundsMax, tool.boundsMax)
        case .subtract: result.volume -= tool.volume
        case .intersect: result.volume = min(target.volume, tool.volume)
        }
        guard result.volume > 0 else { throw FakeKernelError(description: "the operation left no solid") }
        return result
    }

    func transform(_ body: FakeBody, by placement: ResolvedPlacement) throws -> FakeBody {
        FakeBody(
            volume: body.volume, boundsMin: body.boundsMin + placement.translation,
            boundsMax: body.boundsMax + placement.translation, topology: body.topology)
    }

    /// Each selected edge takes one unit of volume and adds a face `<feature>.face[i]`.
    func fillet(_ body: FakeBody, edges: [Int], radius: Double, feature: String) throws -> FakeBody {
        try dressUp(body, edges, radius, feature)
    }

    func chamfer(_ body: FakeBody, edges: [Int], distance: Double, feature: String) throws -> FakeBody {
        try dressUp(body, edges, distance, feature)
    }

    func shell(_ body: FakeBody, faces: [Int], thickness: Double, feature _: String) throws -> FakeBody {
        try positive(thickness)
        var result = body
        result.volume -= thickness
        result.topology.faces = body.topology.faces.enumerated().filter { !faces.contains($0.offset) }.map(\.element)
        result.topology.edges = []
        return result
    }

    private func dressUp(_ body: FakeBody, _ edges: [Int], _ size: Double, _ feature: String) throws -> FakeBody {
        try positive(size)
        guard size < 100 else { throw FakeKernelError(description: "too large for the edges") }
        var result = body
        result.volume -= Double(edges.count)
        result.topology.faces += edges.indices.map { index in
            FaceDescriptor(
                names: ["\(feature).face[\(index)]"], surface: .cylinder,
                centroid: body.topology.edges[edges[index]].midpoint, area: 1, radius: size)
        }
        result.topology.edges = body.topology.edges.enumerated().filter { !edges.contains($0.offset) }.map(\.element)
        return result
    }

    /// The bounding box of the profile's curve ends swept from `from` to `to`; its volume is that box's.
    func extrude(_ profile: SketchProfile, from: Double, to: Double, feature: String) throws -> FakeBody {
        let curves = profile.regions.flatMap { $0.outer + $0.holes.flatMap(\.self) }
        let points = curves.flatMap { curve in
            [from, to].flatMap { offset in
                [curve.geometry.start, curve.geometry.end].map {
                    profile.frame.point($0) + offset * profile.frame.normal
                }
            }
        }
        let low = points.dropFirst().reduce(points[0]) { simd_min($0, $1) }
        let high = points.dropFirst().reduce(points[0]) { simd_max($0, $1) }
        let size = high - low
        let faces = curves.map {
            FaceDescriptor(names: ["\(feature).side[\($0.entity)]"], surface: .plane, centroid: .zero, area: 1)
        }
        return FakeBody(
            volume: [size.x, size.y, size.z].filter { $0 > 1e-9 }.reduce(1, *), boundsMin: low, boundsMax: high,
            topology: BodyTopology(faces: faces, edges: []))
    }

    func revolve(
        _ profile: SketchProfile, axisOrigin: SIMD3<Double>, axisDirection: SIMD3<Double>, angleDegrees: Double,
        feature: String
    ) throws -> FakeBody {
        FakeBody(volume: angleDegrees, boundsMin: .zero, boundsMax: SIMD3(1, 1, 1))
    }

    func topology(of body: FakeBody) throws -> BodyTopology {
        body.topology
    }

    func metrics(of body: FakeBody) throws -> BodyMetrics {
        BodyMetrics(
            volume: body.volume, boundsMin: body.boundsMin, boundsMax: body.boundsMax, faceCount: 6, solidCount: 1,
            isValid: true, isClosed: true)
    }

    func mesh(of body: FakeBody) throws -> BodyMesh {
        guard !meshFails(body) else { throw FakeKernelError(description: "no mesh for this body") }
        return BodyMesh(positions: [.zero, SIMD3(1, 0, 0), SIMD3(0, 1, 0)], normals: [], indices: [0, 1, 2])
    }

    /// The gap between the bounds of the operands; a face or edge counts as its body's bounds.
    func distance(_ a: GeometryOperand<FakeBody>, _ b: GeometryOperand<FakeBody>) throws -> DistanceMeasurement {
        onMeasure()
        let (first, second) = (try bounds(of: a), try bounds(of: b))
        let gap = pointwiseMax(pointwiseMax(first.min - second.max, second.min - first.max), .zero)
        let pointA = pointwiseMin(pointwiseMax(second.min, first.min), first.max)
        return DistanceMeasurement(distance: simd_length(gap), pointA: pointA, pointB: pointA + gap)
    }

    func bounds(of operand: GeometryOperand<FakeBody>) throws -> Bounds {
        switch operand {
        case .point(let point): Bounds(min: point, max: point)
        case .body(let body), .face(let body, _), .edge(let body, _): Bounds(min: body.boundsMin, max: body.boundsMax)
        }
    }
}

extension BodyTopology {
    /// The faces and edges of an axis-aligned box from `origin` to `origin + size`, named `<feature>.<role>`.
    static func box(_ feature: String, origin: SIMD3<Double> = .zero, size: SIMD3<Double>) -> BodyTopology {
        let roles: [(String, SIMD3<Double>)] = [
            ("left", SIMD3(-1, 0, 0)), ("right", SIMD3(1, 0, 0)), ("front", SIMD3(0, -1, 0)),
            ("back", SIMD3(0, 1, 0)), ("bottom", SIMD3(0, 0, -1)), ("top", SIMD3(0, 0, 1)),
        ]
        let centre = origin + size / 2
        let faces = roles.map { role, normal in
            FaceDescriptor(
                names: ["\(feature).\(role)"], surface: .plane, centroid: centre + normal * size / 2,
                area: size.x * size.y * size.z / simd_length(abs(normal) * size), normal: normal)
        }
        var edges: [EdgeDescriptor] = []
        for a in faces.indices {
            for b in faces.indices where a < b && abs(simd_dot(faces[a].normal!, faces[b].normal!)) < 0.5 {
                let (na, nb) = (faces[a].normal!, faces[b].normal!)
                let midpoint = centre + (na + nb) * size / 2
                let direction = abs(simd_cross(na, nb))
                let half = direction * size / 2
                edges.append(
                    EdgeDescriptor(
                        faces: [a, b], curve: .line, length: simd_length(direction * size), start: midpoint - half,
                        end: midpoint + half, midpoint: midpoint, direction: direction))
            }
        }
        return BodyTopology(faces: faces, edges: edges)
    }

    static func + (lhs: BodyTopology, rhs: BodyTopology) -> BodyTopology {
        let offset = lhs.faces.count
        let shifted = rhs.edges.map { edge in
            var edge = edge
            edge.faces = edge.faces.map { $0 + offset }
            return edge
        }
        return BodyTopology(faces: lhs.faces + rhs.faces, edges: lhs.edges + shifted)
    }
}
