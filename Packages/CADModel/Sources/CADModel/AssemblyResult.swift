import Foundation

public enum InstanceStatus: Sendable, Equatable, CustomStringConvertible {
    case ok
    case failed(String)

    public var description: String {
        switch self {
        case .ok: "ok"
        case let .failed(reason): "failed: \(reason)"
        }
    }
}

public struct InstanceResult: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let part: UUID
    public let status: InstanceStatus
    /// Where the part sits: the solved placement when joints moved it, else the document placement; nil when the
    /// instance failed.
    public let transform: RigidTransform?
    /// Whether the joints moved the instance away from its document placement.
    public let movedByJoints: Bool
    /// The part's bodies in assembly coordinates, under the part's body names.
    public let bodies: [BodyResult]
    /// The part's own face and edge names for each body, index-aligned with the moved topology. Computed before the
    /// move, because `[n]` pieces are ordered by position and a rotation would reorder them.
    let names: [String: TopologyNames]

    public init(
        id: UUID, name: String, part: UUID, status: InstanceStatus, transform: RigidTransform?, bodies: [BodyResult],
        names: [String: TopologyNames] = [:], movedByJoints: Bool = false
    ) {
        self.movedByJoints = movedByJoints
        self.id = id
        self.name = name
        self.part = part
        self.status = status
        self.transform = transform
        self.bodies = bodies
        self.names = names
    }

    /// The part's names for the faces and edges of one of the instance's bodies.
    public func names(of body: String) -> TopologyNames? {
        names[body] ?? bodies.first { $0.name == body }?.topology.map(TopologyNames.init)
    }
}

public enum JointStatus: Sendable, Equatable, CustomStringConvertible {
    case ok
    /// Holds, but other joints already imply some of what it demands.
    case redundant
    case failed(String)

    public var description: String {
        switch self {
        case .ok: "ok"
        case .redundant: "ok (redundant: other joints already hold it)"
        case .failed(let reason): "failed: \(reason)"
        }
    }

    public var holds: Bool { self == .ok || self == .redundant }
}

public struct JointResult: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let status: JointStatus
    /// The joint's motion; nil for kinds that have none.
    public let motion: JointMotion?
    /// The driven value when the joint is driven and holds, else the value measured at the solved placements.
    public let value: Double?
    public let minimum: Double?
    public let maximum: Double?
    /// Whether a value drives the joint.
    public let driven: Bool
    /// How many ways the joint still lets its instances move against each other.
    public let freedoms: Int

    public init(
        id: UUID, name: String, status: JointStatus, motion: JointMotion? = nil, value: Double? = nil,
        minimum: Double? = nil, maximum: Double? = nil, driven: Bool = false, freedoms: Int = 0
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.motion = motion
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
        self.driven = driven
        self.freedoms = freedoms
    }

    /// Whether a free joint rests outside its limits.
    public var isOutsideLimits: Bool {
        guard let value else { return false }
        return value < (minimum ?? -.infinity) - 1e-9 || value > (maximum ?? .infinity) + 1e-9
    }
}

public struct AssemblyResult: Sendable, Equatable {
    public let instances: [InstanceResult]
    public let joints: [JointResult]

    public init(instances: [InstanceResult], joints: [JointResult] = []) {
        self.instances = instances
        self.joints = joints
    }

    public func joint(id: UUID) -> JointResult? {
        joints.first { $0.id == id }
    }

    public func joint(named name: String) -> JointResult? {
        joints.first { $0.name == name }
    }

    public func instance(id: UUID) -> InstanceResult? {
        instances.first { $0.id == id }
    }

    public func instance(named name: String) -> InstanceResult? {
        instances.first { $0.name == name }
    }
}
