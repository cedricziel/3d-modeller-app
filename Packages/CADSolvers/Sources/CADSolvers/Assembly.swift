import simd

/// A rotation followed by a translation. The rotation's columns are the moved axes in the outer coordinates.
public struct RigidPlacement: Sendable, Hashable {
    public var rotation: simd_double3x3
    public var translation: SIMD3<Double>

    public static let identity = RigidPlacement()

    public init(rotation: simd_double3x3 = matrix_identity_double3x3, translation: SIMD3<Double> = .zero) {
        self.rotation = rotation
        self.translation = translation
    }

    public func point(_ p: SIMD3<Double>) -> SIMD3<Double> {
        rotation * p + translation
    }

    /// `local` expressed in the coordinates this placement lives in.
    public func composed(with local: RigidPlacement) -> RigidPlacement {
        RigidPlacement(rotation: rotation * local.rotation, translation: point(local.translation))
    }

    public var inverse: RigidPlacement {
        let transposed = rotation.transpose
        return RigidPlacement(rotation: transposed, translation: -(transposed * translation))
    }

    public static func == (lhs: RigidPlacement, rhs: RigidPlacement) -> Bool {
        lhs.rotation == rhs.rotation && lhs.translation == rhs.translation
    }

    public func hash(into hasher: inout Hasher) {
        for column in [rotation.columns.0, rotation.columns.1, rotation.columns.2, translation] {
            hasher.combine(column.x)
            hasher.combine(column.y)
            hasher.combine(column.z)
        }
    }
}

public struct AssemblyBody: Sendable, Hashable {
    public var placement: RigidPlacement
    /// Held where it is; at least one body must be grounded for joints to solve.
    public var grounded: Bool

    public init(placement: RigidPlacement, grounded: Bool = false) {
        self.placement = placement
        self.grounded = grounded
    }
}

/// How two marker frames may move against each other. In every kind the frames' z axes point the same way.
public enum AssemblyJointKind: Sendable, Hashable, CaseIterable {
    /// The frames coincide.
    case fixed
    /// The origins coincide; B turns about the common z axis.
    case revolute
    /// B's origin slides along A's z axis without turning.
    case slider
    /// B's origin slides along A's z axis and turns about it.
    case cylindrical
    /// The origins coincide; B turns freely.
    case ball
    /// B's origin stays in A's xy plane; B slides in it and turns about z.
    case planar
}

public struct AssemblyJoint: Sendable, Hashable {
    public var kind: AssemblyJointKind
    public var bodyA: Int
    /// The marker frame in body A's coordinates.
    public var markerA: RigidPlacement
    public var bodyB: Int
    /// The marker frame in body B's coordinates.
    public var markerB: RigidPlacement

    public init(
        _ kind: AssemblyJointKind, _ bodyA: Int, _ markerA: RigidPlacement, _ bodyB: Int, _ markerB: RigidPlacement
    ) {
        self.kind = kind
        self.bodyA = bodyA
        self.markerA = markerA
        self.bodyB = bodyB
        self.markerB = markerB
    }
}

public struct AssemblySystem: Sendable, Hashable {
    public var bodies: [AssemblyBody]
    public var joints: [AssemblyJoint]

    public init(bodies: [AssemblyBody] = [], joints: [AssemblyJoint] = []) {
        self.bodies = bodies
        self.joints = joints
    }
}
