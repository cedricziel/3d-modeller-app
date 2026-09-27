import Foundation

/// A part placed in the assembly.
public struct Instance: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// The id of the part it places.
    public var part: UUID
    /// One body of the part, or every body the part builds when nil.
    public var body: String?
    public var placement: Placement
    public var grounded: Bool
    /// Overrides the part's appearance for this instance.
    public var appearance: Appearance?

    public init(
        id: UUID = UUID(), name: String, part: UUID, body: String? = nil, placement: Placement = .identity,
        grounded: Bool = false, appearance: Appearance? = nil
    ) {
        self.appearance = appearance
        self.id = id
        self.name = name
        self.part = part
        self.body = body
        self.placement = placement
        self.grounded = grounded
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        part = try container.decode(UUID.self, forKey: .part)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        placement = try container.decodeIfPresent(Placement.self, forKey: .placement) ?? .identity
        grounded = try container.decodeIfPresent(Bool.self, forKey: .grounded) ?? false
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance)
    }
}

public struct Assembly: Codable, Sendable, Hashable {
    public var instances: [Instance]
    public var joints: [Joint]

    public init(instances: [Instance] = [], joints: [Joint] = []) {
        self.instances = instances
        self.joints = joints
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        instances = try container.decodeIfPresent([Instance].self, forKey: .instances) ?? []
        joints = try container.decodeIfPresent([Joint].self, forKey: .joints) ?? []
    }
}

public extension CADDocument {
    var instances: [Instance] {
        assembly?.instances ?? []
    }

    func part(id: UUID) -> Part? {
        parts.first { $0.id == id }
    }

    func instance(named name: String) -> Instance? {
        instances.first { $0.name == name }
    }

    var joints: [Joint] {
        assembly?.joints ?? []
    }

    func joint(named name: String) -> Joint? {
        joints.first { $0.name == name }
    }
}
