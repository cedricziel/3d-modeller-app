import Foundation

/// How a joint lets its two frames move against each other. In every kind the frames' z axes point the same way.
public enum JointKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// The frames coincide.
    case fixed
    /// The origins coincide; b turns about the common z axis.
    case revolute
    /// b slides along a's z axis without turning.
    case slider
    /// b slides along a's z axis and turns about it.
    case cylindrical
    /// The origins coincide; b turns freely.
    case ball
    /// b's origin stays in a's xy plane; b slides in it and turns about z.
    case planar
}

/// Moves a frame by (x, y, z) along its own axes (mm), then turns it by `angle` degrees about its own z axis.
public struct JointOffset: Codable, Sendable, Hashable {
    public var x: Scalar
    public var y: Scalar
    public var z: Scalar
    public var angle: Scalar

    public init(x: Scalar = 0, y: Scalar = 0, z: Scalar = 0, angle: Scalar = 0) {
        self.x = x
        self.y = y
        self.z = z
        self.angle = angle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decodeIfPresent(Scalar.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(Scalar.self, forKey: .y) ?? 0
        z = try container.decodeIfPresent(Scalar.self, forKey: .z) ?? 0
        angle = try container.decodeIfPresent(Scalar.self, forKey: .angle) ?? 0
    }

    var scalars: [(field: String, value: Scalar)] { [("x", x), ("y", y), ("z", z), ("angle", angle)] }
}

/// A frame on an instance: a face, refined by an edge of the same body, then offset. See `GeometryFrame`.
public struct JointFrameRef: Codable, Sendable, Hashable {
    public var instance: UUID
    /// One body of the instance, needed when the face's name exists in several.
    public var body: String?
    public var face: GeometryReference
    public var edge: GeometryReference?
    public var offset: JointOffset?

    public init(
        instance: UUID, body: String? = nil, face: GeometryReference, edge: GeometryReference? = nil,
        offset: JointOffset? = nil
    ) {
        self.instance = instance
        self.body = body
        self.face = face
        self.edge = edge
        self.offset = offset
    }
}

/// The range a joint may be driven through, in its motion's unit (degrees or mm). Free joints are not held inside
/// it.
public struct JointLimits: Codable, Sendable, Hashable {
    public var min: Scalar?
    public var max: Scalar?

    public init(min: Scalar? = nil, max: Scalar? = nil) {
        self.min = min
        self.max = max
    }
}

/// Two frames on two instances held together. Side b's frame is turned half a turn about its x axis first, so two
/// faces meet flush with their outward normals facing each other; `flip` keeps it unturned.
public struct Joint: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: JointKind
    public var a: JointFrameRef
    public var b: JointFrameRef
    public var flip: Bool
    public var limits: JointLimits?
    /// Where the joint is driven to, in its motion's unit; nil leaves the motion free.
    public var value: Scalar?

    public init(
        id: UUID = UUID(), name: String, kind: JointKind, a: JointFrameRef, b: JointFrameRef, flip: Bool = false,
        limits: JointLimits? = nil, value: Scalar? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.a = a
        self.b = b
        self.flip = flip
        self.limits = limits
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(JointKind.self, forKey: .kind)
        a = try container.decode(JointFrameRef.self, forKey: .a)
        b = try container.decode(JointFrameRef.self, forKey: .b)
        flip = try container.decodeIfPresent(Bool.self, forKey: .flip) ?? false
        limits = try container.decodeIfPresent(JointLimits.self, forKey: .limits)
        value = try container.decodeIfPresent(Scalar.self, forKey: .value)
    }
}

/// The one motion a joint can be driven along.
public enum JointMotion: Sendable, Hashable {
    /// Degrees from a's x axis to b's x axis, about a's z axis.
    case angle
    /// Millimetres from a's origin to b's origin, along a's z axis.
    case travel

    public var unit: String {
        switch self {
        case .angle: "°"
        case .travel: " mm"
        }
    }

    public func format(_ value: Double) -> String {
        Scalar.format((value * 10_000).rounded() / 10_000) + unit
    }
}

extension JointKind {
    /// How many ways the joint lets b move against a.
    public var freedoms: Int {
        switch self {
        case .fixed: 0
        case .revolute, .slider: 1
        case .cylindrical: 2
        case .ball, .planar: 3
        }
    }

    /// The motion a value drives; a cylindrical joint is driven along its axis and keeps turning freely.
    public var motion: JointMotion? {
        switch self {
        case .revolute: .angle
        case .slider, .cylindrical: .travel
        case .fixed, .ball, .planar: nil
        }
    }
}
