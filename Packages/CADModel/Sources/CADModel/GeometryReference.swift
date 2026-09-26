import Foundation

/// A reference to faces or edges of a body, resolved on every rebuild. A name picks exactly one face (`Box1.top`,
/// `Box1.top[1]`) or edge (`edge(Box1.front, Box1.top)`); a filter (`parallel Z and farthest +X`) picks every match.
public enum GeometryReference: Sendable, Hashable {
    case name(String)
    case filter(String)

    static let filterKeywords: Set<String> = [
        "edges", "faces", "parallel", "perpendicular", "normal", "type", "circular", "farthest", "on",
    ]

    /// A text whose first word is a filter keyword is a filter; anything else is a name.
    public init(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        self = Self.filterKeywords.contains(first) ? .filter(trimmed) : .name(trimmed)
    }

    public var text: String {
        switch self {
        case .name(let text), .filter(let text): text
        }
    }

    /// The reference with every `old.` prefix that names the feature `old` changed to `new.`.
    public func renamingFeature(_ old: String, to new: String) -> GeometryReference {
        let renamed = Self.rename(text, old, new)
        return switch self {
        case .name: .name(renamed)
        case .filter: .filter(renamed)
        }
    }

    static func rename(_ text: String, _ old: String, _ new: String) -> String {
        let characters = Array(text)
        let target = Array(old + ".")
        var result: [Character] = []
        var index = 0
        while index < characters.count {
            let atBoundary = index == 0 || !(characters[index - 1].isIdentifierStart || characters[index - 1].isDigit)
            if atBoundary, characters[index...].starts(with: target) {
                result += Array(new + ".")
                index += target.count
            } else {
                result.append(characters[index])
                index += 1
            }
        }
        return String(result)
    }
}

extension GeometryReference: CustomStringConvertible {
    public var description: String {
        switch self {
        case .name(let text): text
        case .filter(let text): "\"\(text)\""
        }
    }
}

extension GeometryReference: Codable {
    private enum CodingKeys: String, CodingKey { case name, filter }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch (
            try container.decodeIfPresent(String.self, forKey: .name),
            try container.decodeIfPresent(String.self, forKey: .filter)
        )
        {
        case (let name?, nil): self = .name(name)
        case (nil, let filter?): self = .filter(filter)
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "A reference has either a name or a filter"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .name(let name): try container.encode(name, forKey: .name)
        case .filter(let filter): try container.encode(filter, forKey: .filter)
        }
    }
}

public struct ReferenceError: Error, Sendable, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
