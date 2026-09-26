public struct SketchPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// Angles are radians; an arc runs counter-clockwise from `startAngle` to `endAngle`. Solved arcs
/// come back with `startAngle` in [0, 2π) and `endAngle` in (`startAngle`, `startAngle` + 2π].
public enum SketchGeometry: Sendable, Hashable {
    case point(SketchPoint)
    case line(start: SketchPoint, end: SketchPoint)
    case circle(center: SketchPoint, radius: Double)
    case arc(center: SketchPoint, radius: Double, startAngle: Double, endAngle: Double)
}

public struct SketchEntity: Sendable, Hashable {
    public var geometry: SketchGeometry
    public var construction: Bool

    public init(_ geometry: SketchGeometry, construction: Bool = false) {
        self.geometry = geometry
        self.construction = construction
    }

    public static func point(_ x: Double, _ y: Double, construction: Bool = false) -> SketchEntity {
        SketchEntity(.point(SketchPoint(x, y)), construction: construction)
    }

    public static func line(
        _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, construction: Bool = false
    ) -> SketchEntity {
        SketchEntity(.line(start: SketchPoint(x1, y1), end: SketchPoint(x2, y2)), construction: construction)
    }

    public static func circle(center: SketchPoint, radius: Double, construction: Bool = false) -> SketchEntity {
        SketchEntity(.circle(center: center, radius: radius), construction: construction)
    }

    public static func arc(
        center: SketchPoint, radius: Double, from startAngle: Double, to endAngle: Double,
        construction: Bool = false
    ) -> SketchEntity {
        SketchEntity(
            .arc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle),
            construction: construction
        )
    }
}

/// A point of an entity: `.point` of a point entity, `.start`/`.end` of a line or arc,
/// `.center` of a circle or arc.
public enum SketchPointRef: Sendable, Hashable {
    case point(Int)
    case start(Int)
    case end(Int)
    case center(Int)
}

/// Entities are referenced by index into `Sketch.entities`. Lengths are unitless, angles radians.
public enum SketchConstraint: Sendable, Hashable {
    case coincident(SketchPointRef, SketchPointRef)
    case horizontal(Int)
    case vertical(Int)
    case parallel(Int, Int)
    case perpendicular(Int, Int)
    /// Edge tangency of a line and a circle or arc, or of two circles or arcs.
    case tangent(Int, Int)
    /// The two endpoints coincide and their curves are tangent there.
    case tangentAt(SketchPointRef, SketchPointRef)
    /// Two lines of equal length, or two circles or arcs of equal radius.
    case equal(Int, Int)
    case distance(SketchPointRef, SketchPointRef, Double)
    case pointLineDistance(SketchPointRef, line: Int, Double)
    /// Counter-clockwise from the first line's direction to the second's.
    case angle(Int, Int, Double)
    case radius(Int, Double)
    case diameter(Int, Double)
    /// Holds the point at its given position.
    case fixed(SketchPointRef)
    /// On the infinite line through the line entity.
    case pointOnLine(SketchPointRef, line: Int)
    /// On the full circle of a circle or arc.
    case pointOnCircle(SketchPointRef, curve: Int)
}

public struct Sketch: Sendable, Hashable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]

    public init(entities: [SketchEntity] = [], constraints: [SketchConstraint] = []) {
        self.entities = entities
        self.constraints = constraints
    }
}
