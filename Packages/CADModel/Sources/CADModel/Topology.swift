public enum GeometryKind: String, Sendable, Codable, CaseIterable {
    case faces, edges

    var singular: String { self == .faces ? "face" : "edge" }
}

public enum SurfaceKind: String, Sendable, Codable, CaseIterable {
    case plane, cylinder, cone, sphere, torus, other
}

public enum CurveKind: String, Sendable, Codable, CaseIterable {
    case line, circle, other
}

/// A face of a body as the kernel reports it. `names` come from the features that created or changed the face,
/// primary first.
public struct FaceDescriptor: Sendable, Equatable {
    public var names: [String]
    public var surface: SurfaceKind
    public var centroid: SIMD3<Double>
    public var area: Double
    /// The outward normal of a planar face.
    public var normal: SIMD3<Double>?
    /// A point on the axis of a cylinder, cone or torus, or the centre of a sphere.
    public var axisOrigin: SIMD3<Double>?
    public var axis: SIMD3<Double>?
    public var radius: Double?

    public init(
        names: [String], surface: SurfaceKind, centroid: SIMD3<Double>, area: Double, normal: SIMD3<Double>? = nil,
        axisOrigin: SIMD3<Double>? = nil, axis: SIMD3<Double>? = nil, radius: Double? = nil
    ) {
        self.names = names
        self.surface = surface
        self.centroid = centroid
        self.area = area
        self.normal = normal
        self.axisOrigin = axisOrigin
        self.axis = axis
        self.radius = radius
    }
}

public struct EdgeDescriptor: Sendable, Equatable {
    /// Indices of the adjacent faces in `BodyTopology.faces`.
    public var faces: [Int]
    public var curve: CurveKind
    public var length: Double
    public var start: SIMD3<Double>
    public var end: SIMD3<Double>
    public var midpoint: SIMD3<Double>
    public var direction: SIMD3<Double>?
    public var center: SIMD3<Double>?
    public var axis: SIMD3<Double>?
    public var radius: Double?

    public init(
        faces: [Int], curve: CurveKind, length: Double, start: SIMD3<Double>, end: SIMD3<Double>,
        midpoint: SIMD3<Double>, direction: SIMD3<Double>? = nil, center: SIMD3<Double>? = nil,
        axis: SIMD3<Double>? = nil, radius: Double? = nil
    ) {
        self.faces = faces
        self.curve = curve
        self.length = length
        self.start = start
        self.end = end
        self.midpoint = midpoint
        self.direction = direction
        self.center = center
        self.axis = axis
        self.radius = radius
    }
}

public struct BodyTopology: Sendable, Equatable {
    public var faces: [FaceDescriptor]
    public var edges: [EdgeDescriptor]

    public init(faces: [FaceDescriptor], edges: [EdgeDescriptor]) {
        self.faces = faces
        self.edges = edges
    }

    func count(_ kind: GeometryKind) -> Int { kind == .faces ? faces.count : edges.count }

    /// Where a face or edge sits: a face's centroid, an edge's midpoint.
    func centre(_ kind: GeometryKind, _ index: Int) -> SIMD3<Double> {
        kind == .faces ? faces[index].centroid : edges[index].midpoint
    }
}
