public protocol GeometryKernel: Sendable {
    associatedtype Body: Sendable

    /// Every call that creates or changes faces takes the name of the feature, which the kernel uses to name the
    /// faces (`Box1.top`, `Fillet1.face[0]`); see `BodyTopology`.
    func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement, feature: String) throws
        -> Body
    func cylinder(radius: Double, height: Double, placement: ResolvedPlacement, feature: String) throws -> Body
    func sphere(radius: Double, placement: ResolvedPlacement, feature: String) throws -> Body
    func cone(
        bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement, feature: String
    ) throws -> Body
    func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement, feature: String) throws -> Body
    func boolean(_ operation: BooleanOperation, _ target: Body, _ tool: Body, feature: String) throws -> Body
    func transform(_ body: Body, by placement: ResolvedPlacement) throws -> Body
    /// `edges` and `faces` index into `topology(of: body)`.
    func fillet(_ body: Body, edges: [Int], radius: Double, feature: String) throws -> Body
    func chamfer(_ body: Body, edges: [Int], distance: Double, feature: String) throws -> Body
    /// Hollows the body with walls `thickness` thick inside its outline, open where `faces` were.
    func shell(_ body: Body, faces: [Int], thickness: Double, feature: String) throws -> Body
    func topology(of body: Body) throws -> BodyTopology
    func metrics(of body: Body) throws -> BodyMetrics
    func mesh(of body: Body) throws -> BodyMesh
}

public struct BodyMetrics: Sendable, Equatable {
    public var volume: Double?
    public var boundsMin: SIMD3<Double>
    public var boundsMax: SIMD3<Double>
    public var faceCount: Int
    public var solidCount: Int
    public var isValid: Bool
    public var isClosed: Bool

    public init(
        volume: Double?, boundsMin: SIMD3<Double>, boundsMax: SIMD3<Double>, faceCount: Int, solidCount: Int,
        isValid: Bool, isClosed: Bool
    ) {
        self.volume = volume
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
        self.faceCount = faceCount
        self.solidCount = solidCount
        self.isValid = isValid
        self.isClosed = isClosed
    }
}

public struct BodyMesh: Sendable, Equatable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var indices: [UInt32]

    public init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
    }

    public var triangleCount: Int { indices.count / 3 }
}
