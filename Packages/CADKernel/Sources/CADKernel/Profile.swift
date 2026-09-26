import simd

/// A plane in space with its own 2D coordinates: `x` and `y` map to `xAxis` and `yAxis`.
public struct ProfilePlane: Sendable, Hashable {
    public var origin: SIMD3<Double>
    public var xAxis: SIMD3<Double>
    public var yAxis: SIMD3<Double>

    public init(origin: SIMD3<Double>, xAxis: SIMD3<Double>, yAxis: SIMD3<Double>) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
    }

    public var normal: SIMD3<Double> { simd_normalize(simd_cross(xAxis, yAxis)) }

    public func point(_ p: SIMD2<Double>) -> SIMD3<Double> { origin + p.x * xAxis + p.y * yAxis }

    func offset(by distance: Double) -> ProfilePlane {
        ProfilePlane(origin: origin + distance * normal, xAxis: xAxis, yAxis: yAxis)
    }
}

public enum ProfileGeometry: Sendable, Hashable {
    case line(SIMD2<Double>, SIMD2<Double>)
    /// Runs from `start` through `mid` to `end`, clockwise or counter-clockwise.
    case arc(center: SIMD2<Double>, radius: Double, start: SIMD2<Double>, mid: SIMD2<Double>, end: SIMD2<Double>)
    case circle(center: SIMD2<Double>, radius: Double)
}

/// A curve of a profile loop; `name` becomes part of the names of the faces it sweeps (`F.side[<name>]`).
public struct ProfileCurve: Sendable, Hashable {
    public var name: String
    public var geometry: ProfileGeometry

    public init(name: String, geometry: ProfileGeometry) {
        self.name = name
        self.geometry = geometry
    }
}

/// A face to sweep: its outer loop and its holes. Each loop's curves are ordered so each ends where the next starts.
public struct ProfileRegion: Sendable, Hashable {
    public var outer: [ProfileCurve]
    public var holes: [[ProfileCurve]]

    public init(outer: [ProfileCurve], holes: [[ProfileCurve]]) {
        self.outer = outer
        self.holes = holes
    }
}

public struct Profile: Sendable, Hashable {
    public var plane: ProfilePlane
    public var regions: [ProfileRegion]

    public init(plane: ProfilePlane, regions: [ProfileRegion]) {
        self.plane = plane
        self.regions = regions
    }

    var curves: [ProfileCurve] { regions.flatMap { $0.outer + $0.holes.flatMap(\.self) } }
}
