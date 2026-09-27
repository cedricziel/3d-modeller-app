import Foundation

public struct Part: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var features: [Feature]
    /// How its bodies look, unless an instance overrides it; nil leaves the colour to the viewer.
    public var appearance: Appearance?

    public init(id: UUID = UUID(), name: String, features: [Feature] = [], appearance: Appearance? = nil) {
        self.id = id
        self.name = name
        self.features = features
        self.appearance = appearance
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        features = try container.decodeIfPresent([Feature].self, forKey: .features) ?? []
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance)
    }
}

public enum DocumentError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case unsupportedFormat(Int)
    case unsupportedUnits(String)
    case duplicateID(UUID)

    public var description: String {
        switch self {
        case .unsupportedFormat(let format):
            "Unsupported document format \(format); this app reads format \(CADDocument.format)"
        case .unsupportedUnits(let units): "Unsupported units '\(units)'; documents use \(CADDocument.units)"
        case .duplicateID(let id): "More than one part, feature, instance or joint has the id \(id)"
        }
    }

    public var errorDescription: String? { description }
}

public struct CADDocument: Codable, Sendable, Hashable {
    public static let format = 1
    public static let units = "mm"

    public var parameters: [Parameter]
    public var parts: [Part]
    public var assembly: Assembly?

    public init(parameters: [Parameter] = [], parts: [Part] = [Part(name: "Part1")], assembly: Assembly? = nil) {
        self.parameters = parameters
        self.parts = parts
        self.assembly = assembly
    }

    private enum CodingKeys: String, CodingKey { case format, units, parameters, parts, assembly }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = try container.decode(Int.self, forKey: .format)
        guard format == Self.format else { throw DocumentError.unsupportedFormat(format) }
        let units = try container.decode(String.self, forKey: .units)
        guard units == Self.units else { throw DocumentError.unsupportedUnits(units) }
        parameters = try container.decodeIfPresent([Parameter].self, forKey: .parameters) ?? []
        parts = try container.decodeIfPresent([Part].self, forKey: .parts) ?? []
        assembly = try container.decodeIfPresent(Assembly.self, forKey: .assembly)
        var ids: Set<UUID> = []
        let assemblyIDs = (assembly?.instances.map(\.id) ?? []) + (assembly?.joints.map(\.id) ?? [])
        for id in parts.map(\.id) + parts.flatMap(\.features).map(\.id) + assemblyIDs where !ids.insert(id).inserted {
            throw DocumentError.duplicateID(id)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.format, forKey: .format)
        try container.encode(Self.units, forKey: .units)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(parts, forKey: .parts)
        try container.encode(assembly, forKey: .assembly)
    }
}

extension CADDocument {
    public init(json: Data) throws {
        self = try JSONDecoder().decode(CADDocument.self, from: json)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func feature(id: UUID) -> Feature? {
        parts.lazy.flatMap(\.features).first { $0.id == id }
    }

    @discardableResult
    public mutating func updateFeature(id: UUID, _ change: (inout Feature) -> Void) -> Bool {
        for part in parts.indices {
            if let index = parts[part].features.firstIndex(where: { $0.id == id }) {
                change(&parts[part].features[index])
                return true
            }
        }
        return false
    }

    @discardableResult
    public mutating func removeFeature(id: UUID) -> Feature? {
        for part in parts.indices {
            if let index = parts[part].features.firstIndex(where: { $0.id == id }) {
                return parts[part].features.remove(at: index)
            }
        }
        return nil
    }
}
