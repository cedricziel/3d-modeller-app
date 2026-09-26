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
    /// Sweeps the profile along its normal from offset `from` to `to` (mm). Faces are named `<feature>.start`,
    /// `<feature>.end` and `<feature>.side[<curve name>]`.
    func extrude(_ profile: SketchProfile, from: Double, to: Double, feature: String) throws -> Body
    /// Turns the profile about the axis by `angleDegrees`, counter-clockwise about `axisDirection` (a unit vector).
    func revolve(
        _ profile: SketchProfile, axisOrigin: SIMD3<Double>, axisDirection: SIMD3<Double>, angleDegrees: Double,
        feature: String
    ) throws -> Body
    func topology(of body: Body) throws -> BodyTopology
    func metrics(of body: Body) throws -> BodyMetrics
    func mesh(of body: Body) throws -> BodyMesh
    /// The minimum distance between the operands; 0 when they touch or overlap.
    func distance(_ a: GeometryOperand<Body>, _ b: GeometryOperand<Body>) throws -> DistanceMeasurement
    func bounds(of operand: GeometryOperand<Body>) throws -> Bounds
}

/// What a measurement is taken on; face and edge indices follow `topology(of:)`.
public enum GeometryOperand<Body: Sendable>: Sendable {
    case point(SIMD3<Double>)
    case body(Body)
    case face(Body, Int)
    case edge(Body, Int)
}

public struct DistanceMeasurement: Sendable, Equatable {
    public var distance: Double
    /// The closest points on the first and the second operand.
    public var pointA: SIMD3<Double>
    public var pointB: SIMD3<Double>

    public init(distance: Double, pointA: SIMD3<Double>, pointB: SIMD3<Double>) {
        self.distance = distance
        self.pointA = pointA
        self.pointB = pointB
    }
}

public struct Bounds: Sendable, Equatable {
    public var min: SIMD3<Double>
    public var max: SIMD3<Double>

    public init(min: SIMD3<Double>, max: SIMD3<Double>) {
        self.min = min
        self.max = max
    }
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
