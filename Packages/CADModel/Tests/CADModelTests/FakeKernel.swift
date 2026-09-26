import CADModel
import Foundation
import Synchronization
import simd

struct FakeBody: Sendable, Equatable {
    var volume: Double
    var topology = BodyTopology(faces: [], edges: [])
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
                area: 1, normal: normal)
        }
        var edges: [EdgeDescriptor] = []
        for a in faces.indices {
            for b in faces.indices where a < b && abs(simd_dot(faces[a].normal!, faces[b].normal!)) < 0.5 {
                let (na, nb) = (faces[a].normal!, faces[b].normal!)
                let midpoint = centre + (na + nb) * size / 2
                let direction = simd_cross(na, nb)
                let half = abs(direction) * size / 2
                edges.append(
                    EdgeDescriptor(
                        faces: [a, b], curve: .line, length: simd_length(abs(direction) * size),
                        start: midpoint - half, end: midpoint + half, midpoint: midpoint, direction: abs(direction)))
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

struct FakeKernelError: Error, CustomStringConvertible {
    let description: String
}

final class FakeKernel: GeometryKernel {
    private let log = Mutex<[String]>([])
    private let mainThreadCalls = Mutex(0)
    let onCall: @Sendable (String) -> Void

    init(onCall: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onCall = onCall
    }

    var calls: [String] {
        log.withLock { $0 }
    }

    var callsOnMainThread: Int {
        mainThreadCalls.withLock { $0 }
    }

    private func record(_ call: String) {
        log.withLock { $0.append(call) }
        if Thread.isMainThread {
            mainThreadCalls.withLock { $0 += 1 }
        }
        onCall(call)
    }

    private static func text(_ p: ResolvedPlacement) -> String {
        let t = p.translation
        let a = p.rotationAxis
        return "@(\(Scalar.number(t.x)),\(Scalar.number(t.y)),\(Scalar.number(t.z)))"
            + " \(Scalar.number(p.rotationDegrees))°(\(Scalar.number(a.x)),\(Scalar.number(a.y)),\(Scalar.number(a.z)))"
    }

    private static func requirePositive(_ values: Double...) throws {
        guard values.allSatisfy({ $0 > 0 }) else { throw FakeKernelError(description: "dimensions must be positive") }
    }

    func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement, feature: String) throws
        -> FakeBody
    {
        record("box \(Scalar.number(width))x\(Scalar.number(depth))x\(Scalar.number(height)) \(Self.text(placement))")
        try Self.requirePositive(width, depth, height)
        return FakeBody(
            volume: width * depth * height,
            topology: .box(feature, origin: placement.translation, size: SIMD3(width, depth, height)))
    }

    func cylinder(radius: Double, height: Double, placement: ResolvedPlacement, feature: String) throws -> FakeBody {
        record("cylinder r\(Scalar.number(radius)) h\(Scalar.number(height)) \(Self.text(placement))")
        try Self.requirePositive(radius, height)
        let side = FaceDescriptor(
            names: ["\(feature).side"], surface: .cylinder, centroid: placement.translation, area: 1,
            axisOrigin: placement.translation, axis: SIMD3(0, 0, 1), radius: radius)
        return FakeBody(volume: 100 * radius * radius * height, topology: BodyTopology(faces: [side], edges: []))
    }

    func sphere(radius: Double, placement _: ResolvedPlacement, feature _: String) throws -> FakeBody {
        record("sphere r\(Scalar.number(radius))")
        try Self.requirePositive(radius)
        return FakeBody(volume: 1000 * radius)
    }

    func cone(
        bottomRadius: Double, topRadius: Double, height: Double, placement _: ResolvedPlacement, feature _: String
    ) throws -> FakeBody {
        record("cone")
        guard bottomRadius != topRadius else { throw FakeKernelError(description: "cone radii must differ") }
        return FakeBody(volume: height)
    }

    func torus(majorRadius: Double, minorRadius: Double, placement _: ResolvedPlacement, feature _: String) throws
        -> FakeBody
    {
        record("torus")
        return FakeBody(volume: majorRadius * minorRadius)
    }

    func boolean(_ operation: BooleanOperation, _ target: FakeBody, _ tool: FakeBody, feature _: String) throws
        -> FakeBody
    {
        record("\(operation.rawValue) \(Scalar.number(target.volume)) \(Scalar.number(tool.volume))")
        let volume =
            switch operation {
            case .union: target.volume + tool.volume
            case .subtract: target.volume - tool.volume
            case .intersect: min(target.volume, tool.volume)
            }
        guard volume > 0 else { throw FakeKernelError(description: "The operation left no solid") }
        return FakeBody(volume: volume, topology: target.topology + tool.topology)
    }

    func transform(_ body: FakeBody, by placement: ResolvedPlacement) throws -> FakeBody {
        record("transform \(Scalar.number(body.volume)) \(Self.text(placement))")
        return body
    }

    /// Records the call; each selected edge adds a face `<feature>.face[i]` and takes one unit of volume.
    func fillet(_ body: FakeBody, edges: [Int], radius: Double, feature: String) throws -> FakeBody {
        try dressUp("fillet", body, edges, radius, feature)
    }

    func chamfer(_ body: FakeBody, edges: [Int], distance: Double, feature: String) throws -> FakeBody {
        try dressUp("chamfer", body, edges, distance, feature)
    }

    func shell(_ body: FakeBody, faces: [Int], thickness: Double, feature: String) throws -> FakeBody {
        record("shell \(faces) t\(Scalar.number(thickness)) as \(feature)")
        try Self.requirePositive(thickness)
        var result = body
        result.volume -= thickness
        result.topology.faces = body.topology.faces.enumerated().filter { !faces.contains($0.offset) }.map(\.element)
        result.topology.edges = []
        return result
    }

    private func dressUp(_ name: String, _ body: FakeBody, _ edges: [Int], _ size: Double, _ feature: String) throws
        -> FakeBody
    {
        record("\(name) \(edges) \(Scalar.number(size)) as \(feature)")
        try Self.requirePositive(size)
        guard size < 100 else { throw FakeKernelError(description: "\(name) is too large for the edges") }
        var result = body
        result.volume -= Double(edges.count)
        result.topology.faces += edges.indices.map { index in
            FaceDescriptor(
                names: ["\(feature).face[\(index)]"], surface: .cylinder,
                centroid: body.topology.edges[edges[index]].midpoint,
                area: 1, radius: size)
        }
        result.topology.edges = body.topology.edges.enumerated().filter { !edges.contains($0.offset) }.map(\.element)
        return result
    }

    func topology(of body: FakeBody) throws -> BodyTopology {
        body.topology
    }

    func metrics(of body: FakeBody) throws -> BodyMetrics {
        BodyMetrics(
            volume: body.volume, boundsMin: .zero, boundsMax: SIMD3(1, 1, 1),
            faceCount: 6, solidCount: 1, isValid: true, isClosed: true
        )
    }

    func mesh(of _: FakeBody) throws -> BodyMesh {
        onCall("mesh")
        return BodyMesh(
            positions: [.zero, SIMD3(1, 0, 0), SIMD3(0, 1, 0)], normals: Array(repeating: SIMD3(0, 0, 1), count: 3),
            indices: [0, 1, 2]
        )
    }
}
