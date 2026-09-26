/// A 2D point in a sketch's own coordinates (mm). Encoded as `[x, y]`.
public struct SketchPoint2: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public var simd: SIMD2<Double> { SIMD2(x, y) }
}

public enum SketchBasePlane: String, Sendable, Hashable, Codable, CaseIterable {
    case xy = "XY"
    case xz = "XZ"
    case yz = "YZ"
}

/// Where a sketch lies: a base plane through the origin or a planar face of a body, moved `offset` mm along its
/// normal.
public enum SketchPlane: Sendable, Hashable {
    case base(SketchBasePlane, offset: Scalar = 0)
    case face(body: String, face: GeometryReference, offset: Scalar = 0)

    public var offset: Scalar {
        switch self {
        case .base(_, let offset), .face(_, _, let offset): offset
        }
    }
}

/// Angles are degrees; an arc runs counter-clockwise from `startAngle` to `endAngle`.
public enum SketchEntityGeometry: Sendable, Hashable {
    case point(SketchPoint2)
    case line(start: SketchPoint2, end: SketchPoint2)
    case circle(center: SketchPoint2, radius: Double)
    case arc(center: SketchPoint2, radius: Double, startAngle: Double, endAngle: Double)

    public var typeName: String {
        switch self {
        case .point: "point"
        case .line: "line"
        case .circle: "circle"
        case .arc: "arc"
        }
    }
}

/// A named entity of a sketch. Its geometry is the solver's starting guess; construction entities take part in
/// constraints but never in profiles.
public struct SketchEntity: Sendable, Hashable {
    public var name: String
    public var geometry: SketchEntityGeometry
    public var construction: Bool

    public init(name: String, _ geometry: SketchEntityGeometry, construction: Bool = false) {
        self.name = name
        self.geometry = geometry
        self.construction = construction
    }
}

public enum SketchConstraintKind: String, Sendable, Hashable, Codable, CaseIterable {
    case coincident, horizontal, vertical, parallel, perpendicular, tangent, tangentAt, equal, distance
    case pointLineDistance, angle, radius, diameter, fixed, pointOnLine, pointOnCircle
}

/// A named constraint. `entities` name lines, circles or arcs; `points` name points such as `line1.end`,
/// `arc1.center` or `point1`. `value` is a length in mm or, for `angle`, degrees. `at` places a `fixed` point.
public struct SketchConstraint: Sendable, Hashable {
    public var name: String
    public var kind: SketchConstraintKind
    public var entities: [String]
    public var points: [String]
    public var value: Scalar?
    public var at: [Scalar]?

    public init(
        name: String, _ kind: SketchConstraintKind, entities: [String] = [], points: [String] = [],
        value: Scalar? = nil, at: [Scalar]? = nil
    ) {
        self.name = name
        self.kind = kind
        self.entities = entities
        self.points = points
        self.value = value
        self.at = at
    }
}

public struct SketchFeature: Sendable, Hashable {
    public var plane: SketchPlane
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]
    /// Names of removed entities and constraints, never handed out again, so a reference to an old name cannot
    /// silently land on new geometry.
    public var retiredNames: [String]

    public init(
        plane: SketchPlane, entities: [SketchEntity] = [], constraints: [SketchConstraint] = [],
        retiredNames: [String] = []
    ) {
        self.plane = plane
        self.entities = entities
        self.constraints = constraints
        self.retiredNames = retiredNames
    }
}
