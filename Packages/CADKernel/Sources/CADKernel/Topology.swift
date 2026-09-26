import OCCTSwift
import simd

public enum SurfaceKind: String, Sendable {
    case plane, cylinder, cone, sphere, torus, other
}

public enum CurveKind: String, Sendable {
    case line, circle, other
}

public struct FaceInfo: Sendable, Equatable {
    public let names: [String]
    public let surface: SurfaceKind
    public let centroid: SIMD3<Double>
    public let area: Double
    /// The outward normal of a planar face.
    public let normal: SIMD3<Double>?
    /// A point on the axis of a cylinder, cone or torus, or the centre of a sphere.
    public let axisOrigin: SIMD3<Double>?
    public let axis: SIMD3<Double>?
    public let radius: Double?
}

public struct EdgeInfo: Sendable, Equatable {
    /// Indices of the adjacent faces in `Topology.faces`.
    public let faces: [Int]
    public let curve: CurveKind
    public let length: Double
    public let start: SIMD3<Double>
    public let end: SIMD3<Double>
    public let midpoint: SIMD3<Double>
    public let direction: SIMD3<Double>?
    public let center: SIMD3<Double>?
    public let axis: SIMD3<Double>?
    public let radius: Double?
}

public struct Topology: Sendable, Equatable {
    public let faces: [FaceInfo]
    public let edges: [EdgeInfo]
}

extension Kernel {
    public static func topology(of solid: Solid) throws -> Topology {
        try OCCTSerial.withLock {
            let shape = solid.shape
            let faceShapes = shape.subShapes(ofType: .face)
            guard faceShapes.count == solid.faceNames.count else {
                throw KernelError.operationFailed("match the face names to the faces")
            }
            let faces = zip(faceShapes, solid.faceNames).map { describeFace($0, names: $1) }
            let edges = shape.subShapes(ofType: .edge).compactMap { edge -> EdgeInfo? in
                guard let info = Edge(edge) else { return nil }
                var adjacent: [Int] = []
                for index in shape.adjacentFaces(forEdge: edge) where !adjacent.contains(index) {
                    adjacent.append(index)
                }
                return describeEdge(info, faces: adjacent)
            }
            return Topology(faces: faces, edges: edges)
        }
    }

    private static func describeFace(_ shape: Shape, names: [String]) -> FaceInfo {
        let face = Face(shape)
        let inertia = shape.surfaceInertia
        var surface = SurfaceKind.other
        var (normal, origin, axis, radius): (SIMD3<Double>?, SIMD3<Double>?, SIMD3<Double>?, Double?)
        // The *Properties views borrow the surface's handle without retaining it.
        let geometry = shape.faceSurfaceGeom()
        defer { withExtendedLifetime(geometry) {} }
        switch face?.surfaceType {
        case .plane?:
            surface = .plane
            normal = face?.normal.map(simd_normalize)
        case .cylinder?:
            surface = .cylinder
            if let properties = geometry?.cylinderProperties {
                (origin, axis) = (properties.axis.position, properties.axis.direction)
                radius = positive(properties.radius)
            }
        case .cone?:
            surface = .cone
            if let properties = geometry?.coneProperties {
                (origin, axis) = (properties.axis.position, properties.axis.direction)
            }
        case .sphere?:
            surface = .sphere
            if let properties = geometry?.sphereProperties, let r = positive(properties.radius) {
                (origin, radius) = (properties.center, r)
            }
        case .torus?:
            surface = .torus
            if let properties = geometry?.torusProperties {
                radius = positive(properties.minorRadius)
            }
        default:
            break
        }
        return FaceInfo(
            names: names, surface: surface, centroid: inertia?.centerOfMass ?? .zero, area: inertia?.area ?? 0,
            normal: normal, axisOrigin: origin, axis: axis, radius: radius)
    }

    private static func describeEdge(_ edge: Edge, faces: [Int]) -> EdgeInfo {
        let (start, end) = edge.endpoints
        var midpoint = (start + end) / 2
        if let bounds = edge.parameterBounds, let point = edge.point(at: (bounds.first + bounds.last) / 2) {
            midpoint = point
        }
        var curve = CurveKind.other
        var (direction, center, axis, radius): (SIMD3<Double>?, SIMD3<Double>?, SIMD3<Double>?, Double?)
        switch edge.curveType {
        case .line:
            curve = .line
            if simd_length(end - start) > 0 { direction = simd_normalize(end - start) }
        case .circle:
            curve = .circle
            if let curve = edge.curve3D {
                withExtendedLifetime(curve) {
                    let circle = curve.circleProperties
                    guard let r = positive(circle.radius) else { return }
                    radius = r
                    center = circle.center
                    let normal = simd_cross(circle.xAxis.direction, circle.yAxis.direction)
                    if simd_length(normal) > 0 { axis = simd_normalize(normal) }
                }
            }
        default:
            break
        }
        return EdgeInfo(
            faces: faces, curve: curve, length: edge.length, start: start, end: end, midpoint: midpoint,
            direction: direction, center: center, axis: axis, radius: radius)
    }

    private static func positive(_ value: Double) -> Double? {
        value > 0 && value.isFinite ? value : nil
    }
}
