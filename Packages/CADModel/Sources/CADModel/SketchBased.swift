/// How far an extrude goes along its sketch plane's normal.
public enum ExtrudeExtent: Sendable, Hashable {
    case distance(Scalar)
    /// Half the distance to each side of the plane.
    case symmetric(Scalar)
    /// Through the whole target body, to both sides of the plane.
    case throughAll
    /// To a planar face parallel to the sketch plane.
    case upToFace(body: String, face: GeometryReference)
}

/// Sweeps closed regions of a sketch along its normal. `regions` names an entity of each loop to use; empty means
/// every region.
public struct ExtrudeFeature: Sendable, Hashable {
    public var sketch: String
    public var regions: [String]
    public var extent: ExtrudeExtent
    public var reversed: Bool
    public var operation: SolidOperation

    public init(
        sketch: String, regions: [String] = [], extent: ExtrudeExtent, reversed: Bool = false,
        operation: SolidOperation = .newBody
    ) {
        self.sketch = sketch
        self.regions = regions
        self.extent = extent
        self.reversed = reversed
        self.operation = operation
    }
}

public enum RevolveAxis: Sendable, Hashable {
    /// A line of the same sketch, from its start to its end.
    case sketchLine(String)
    case x, y, z
    /// A straight edge of a body.
    case edge(body: String, edge: GeometryReference)
}

/// Turns closed regions of a sketch about an axis by `angle` degrees, counter-clockwise about the axis direction.
public struct RevolveFeature: Sendable, Hashable {
    public var sketch: String
    public var regions: [String]
    public var axis: RevolveAxis
    public var angle: Scalar
    public var operation: SolidOperation

    public init(
        sketch: String, regions: [String] = [], axis: RevolveAxis, angle: Scalar = 360,
        operation: SolidOperation = .newBody
    ) {
        self.sketch = sketch
        self.regions = regions
        self.axis = axis
        self.angle = angle
        self.operation = operation
    }
}
