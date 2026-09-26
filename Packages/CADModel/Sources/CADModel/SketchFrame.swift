import simd

/// Where a sketch lies in space: its 2D x and y map to `xAxis` and `yAxis` from `origin`.
public struct SketchFrame: Sendable, Hashable {
    public var origin: SIMD3<Double>
    public var xAxis: SIMD3<Double>
    public var yAxis: SIMD3<Double>

    public init(origin: SIMD3<Double>, xAxis: SIMD3<Double>, yAxis: SIMD3<Double>) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
    }

    public var normal: SIMD3<Double> { simd_cross(xAxis, yAxis) }

    public func point(_ p: SIMD2<Double>) -> SIMD3<Double> { origin + p.x * xAxis + p.y * yAxis }

    /// XY: x = X, y = Y, normal +Z. XZ: x = X, y = Z, normal −Y. YZ: x = Y, y = Z, normal +X.
    public static func base(_ plane: SketchBasePlane, offset: Double) -> SketchFrame {
        let (x, y): (SIMD3<Double>, SIMD3<Double>) =
            switch plane {
            case .xy: (SIMD3(1, 0, 0), SIMD3(0, 1, 0))
            case .xz: (SIMD3(1, 0, 0), SIMD3(0, 0, 1))
            case .yz: (SIMD3(0, 1, 0), SIMD3(0, 0, 1))
            }
        return SketchFrame(origin: offset * simd_cross(x, y), xAxis: x, yAxis: y)
    }

    /// The plane of a planar face: the normal points out of the body, the origin is the world origin projected onto
    /// the plane, x is the first world axis that does not stand (nearly) perpendicular on it, y = normal × x.
    public static func face(_ face: FaceDescriptor, offset: Double) -> SketchFrame? {
        guard face.surface == .plane, let normal = face.normal, simd_length(normal) > 0 else { return nil }
        let n = simd_normalize(normal)
        let worldAxes: [SIMD3<Double>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        let projections = worldAxes.map { $0 - simd_dot($0, n) * n }
        guard let projection = projections.first(where: { simd_length($0) > 0.1 }) else { return nil }
        let x = simd_normalize(projection)
        return SketchFrame(origin: (simd_dot(face.centroid, n) + offset) * n, xAxis: x, yAxis: simd_cross(n, x))
    }
}

/// Closed regions of a sketch placed in space, with curve names qualified by the sketch (`Sketch1.line3`).
public struct SketchProfile: Sendable, Equatable {
    public var frame: SketchFrame
    public var regions: [SketchRegion]

    public init(frame: SketchFrame, regions: [SketchRegion]) {
        self.frame = frame
        self.regions = regions
    }
}
