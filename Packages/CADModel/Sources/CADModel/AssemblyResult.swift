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
    /// Where the placement puts the part; nil when the placement did not evaluate.
    public let transform: RigidTransform?
    /// The part's bodies in assembly coordinates, under the part's body names.
    public let bodies: [BodyResult]

    public init(
        id: UUID, name: String, part: UUID, status: InstanceStatus, transform: RigidTransform?, bodies: [BodyResult]
    ) {
        self.id = id
        self.name = name
        self.part = part
        self.status = status
        self.transform = transform
        self.bodies = bodies
    }
}

public struct AssemblyResult: Sendable, Equatable {
    public let instances: [InstanceResult]

    public init(instances: [InstanceResult]) {
        self.instances = instances
    }

    public func instance(id: UUID) -> InstanceResult? {
        instances.first { $0.id == id }
    }

    public func instance(named name: String) -> InstanceResult? {
        instances.first { $0.name == name }
    }
}
