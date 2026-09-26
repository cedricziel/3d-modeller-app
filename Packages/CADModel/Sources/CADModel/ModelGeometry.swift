import simd

public struct BodyKey: Sendable, Hashable, CustomStringConvertible {
    public var part: String
    public var body: String

    public init(part: String, body: String) {
        self.part = part
        self.body = body
    }

    public var description: String { "\(body) (\(part))" }
}

public enum MeasureTarget: Sendable, Equatable {
    case point(SIMD3<Double>)
    case body(BodyKey)
    case face(BodyKey, Int)
    case edge(BodyKey, Int)
}

public struct MeasureError: Error, Sendable, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Kernel measurements on the bodies of one rebuild, with the kernel's body type hidden so the tools can hold it.
public struct ModelGeometry: Sendable {
    private let measureDistance: @Sendable (MeasureTarget, MeasureTarget) throws(MeasureError) -> DistanceMeasurement
    private let measureBounds: @Sendable (MeasureTarget) throws(MeasureError) -> Bounds
    private let measureInterference: @Sendable (BodyKey, BodyKey) throws(MeasureError) -> Double

    public static let empty = ModelGeometry(kernel: NoKernel(), bodies: [:])

    public init<Kernel: GeometryKernel>(kernel: Kernel, bodies: [BodyKey: Kernel.Body]) {
        let measurer = Measurer(kernel: kernel, bodies: bodies)
        measureDistance = { (a, b) throws(MeasureError) in try measurer.distance(a, b) }
        measureBounds = { (target) throws(MeasureError) in try measurer.bounds(of: target) }
        measureInterference = { (a, b) throws(MeasureError) in try measurer.interference(a, b) }
    }

    public func distance(_ a: MeasureTarget, _ b: MeasureTarget) throws(MeasureError) -> DistanceMeasurement {
        if case .point(let p) = a, case .point(let q) = b {
            return DistanceMeasurement(distance: simd_distance(p, q), pointA: p, pointB: q)
        }
        return try measureDistance(a, b)
    }

    public func bounds(of target: MeasureTarget) throws(MeasureError) -> Bounds {
        try measureBounds(target)
    }

    /// The volume two bodies share, by inclusion–exclusion over their union, because the kernel reports an empty
    /// intersection as an error.
    public func interference(_ a: BodyKey, _ b: BodyKey) throws(MeasureError) -> Double {
        try measureInterference(a, b)
    }
}

private struct Measurer<Kernel: GeometryKernel>: Sendable {
    let kernel: Kernel
    let bodies: [BodyKey: Kernel.Body]

    func distance(_ a: MeasureTarget, _ b: MeasureTarget) throws(MeasureError) -> DistanceMeasurement {
        let (a, b) = (try operand(a), try operand(b))
        return try kernelCall { try kernel.distance(a, b) }
    }

    func bounds(of target: MeasureTarget) throws(MeasureError) -> Bounds {
        let target = try operand(target)
        return try kernelCall { try kernel.bounds(of: target) }
    }

    func interference(_ a: BodyKey, _ b: BodyKey) throws(MeasureError) -> Double {
        let (first, second) = (try body(a), try body(b))
        let volumes = try kernelCall {
            let union = try kernel.boolean(.union, first, second, feature: "Interference")
            return try [first, second, union].map { try kernel.metrics(of: $0).volume }
        }
        guard let va = volumes[0], let vb = volumes[1], let vu = volumes[2] else {
            throw MeasureError("the kernel could not compute the volumes")
        }
        let overlap = va + vb - vu
        return overlap > 1e-6 * min(va, vb) ? overlap : 0
    }

    private func body(_ key: BodyKey) throws(MeasureError) -> Kernel.Body {
        guard let body = bodies[key] else { throw MeasureError("\(key) was not built") }
        return body
    }

    private func operand(_ target: MeasureTarget) throws(MeasureError) -> GeometryOperand<Kernel.Body> {
        switch target {
        case .point(let point): .point(point)
        case .body(let key): .body(try body(key))
        case .face(let key, let index): .face(try body(key), index)
        case .edge(let key, let index): .edge(try body(key), index)
        }
    }

    private func kernelCall<T>(_ call: () throws -> T) throws(MeasureError) -> T {
        do { return try call() } catch { throw MeasureError(String(describing: error)) }
    }
}

private struct NoKernel: GeometryKernel {
    typealias Body = Never

    private var unavailable: MeasureError { MeasureError("nothing was built") }

    func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement, feature: String) throws
        -> Never
    { throw unavailable }
    func cylinder(radius: Double, height: Double, placement: ResolvedPlacement, feature: String) throws -> Never {
        throw unavailable
    }
    func sphere(radius: Double, placement: ResolvedPlacement, feature: String) throws -> Never { throw unavailable }
    func cone(
        bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement, feature: String
    ) throws -> Never { throw unavailable }
    func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement, feature: String) throws
        -> Never
    { throw unavailable }
    func boolean(_ operation: BooleanOperation, _ target: Never, _ tool: Never, feature: String) throws -> Never {}
    func transform(_ body: Never, by placement: ResolvedPlacement) throws -> Never {}
    func fillet(_ body: Never, edges: [Int], radius: Double, feature: String) throws -> Never {}
    func chamfer(_ body: Never, edges: [Int], distance: Double, feature: String) throws -> Never {}
    func shell(_ body: Never, faces: [Int], thickness: Double, feature: String) throws -> Never {}
    func topology(of body: Never) throws -> BodyTopology {}
    func metrics(of body: Never) throws -> BodyMetrics {}
    func mesh(of body: Never) throws -> BodyMesh {}
    func distance(_ a: GeometryOperand<Never>, _ b: GeometryOperand<Never>) throws -> DistanceMeasurement {
        throw unavailable
    }
    func bounds(of operand: GeometryOperand<Never>) throws -> Bounds { throw unavailable }
}
