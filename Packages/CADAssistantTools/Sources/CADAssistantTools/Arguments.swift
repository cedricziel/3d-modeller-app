import CADModel
import SwiftUIAssistant

/// Tool arguments checked against the keys a tool accepts; JSON nulls count as absent.
struct Arguments {
    private let values: [String: JSONValue]

    init(_ values: [String: JSONValue], allowed: [String]) throws(ToolError) {
        let unknown = values.keys.filter { !allowed.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw ToolError(
                "Unknown argument \(unknown.map { "'\($0)'" }.joined(separator: ", ")). "
                    + "Accepted: \(allowed.joined(separator: ", ")).")
        }
        self.values = values.filter { !$0.value.isNull }
    }

    var keys: Set<String> { Set(values.keys) }

    func has(_ key: String) -> Bool { values[key] != nil }

    func string(_ key: String) throws(ToolError) -> String? {
        guard let value = values[key] else { return nil }
        guard let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw ToolError("'\(key)' must be a non-empty string.")
        }
        return text
    }

    func requiredString(_ key: String) throws(ToolError) -> String {
        guard let text = try string(key) else { throw ToolError("Missing required argument '\(key)'.") }
        return text
    }

    func bool(_ key: String) throws(ToolError) -> Bool? {
        guard let value = values[key] else { return nil }
        guard let flag = value.boolValue else { throw ToolError("'\(key)' must be true or false.") }
        return flag
    }

    func scalar(_ key: String) throws(ToolError) -> Scalar? {
        try values[key].map { (value) throws(ToolError) in try Self.scalar(value, key) }
    }

    func strings(_ key: String, _ what: String) throws(ToolError) -> [String]? {
        guard let value = values[key] else { return nil }
        guard let items = value.arrayValue else { throw ToolError("'\(key)' must be an array of \(what).") }
        var names: [String] = []
        for item in items {
            guard let name = item.stringValue?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                throw ToolError("'\(key)' must be an array of \(what).")
            }
            names.append(name)
        }
        return names
    }

    func array(_ key: String) throws(ToolError) -> [JSONValue]? {
        guard let value = values[key] else { return nil }
        guard let items = value.arrayValue else { throw ToolError("'\(key)' must be an array.") }
        return items
    }

    func object(_ key: String) throws(ToolError) -> [String: JSONValue]? {
        guard let value = values[key] else { return nil }
        guard let object = value.objectValue else { throw ToolError("'\(key)' must be an object.") }
        return object
    }

    /// A number, or a string holding a number or an expression over parameters.
    static func scalar(_ value: JSONValue, _ key: String) throws(ToolError) -> Scalar {
        switch value {
        case .number(let number) where number.isFinite: return .number(number)
        case .integer(let integer): return .number(Double(integer))
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ToolError("'\(key)' is empty; give a number or an expression.") }
            if let number = Double(trimmed), number.isFinite { return .number(number) }
            return .expression(trimmed)
        default:
            throw ToolError("'\(key)' must be a number or an expression string such as \"width / 2\".")
        }
    }
}

enum Naming {
    static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLetter || first == "_", name.count <= 64 else {
            return false
        }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    static func checkFeatureName(_ name: String, in part: Part, excluding id: UUID? = nil) throws(ToolError) {
        guard isIdentifier(name) else {
            throw ToolError(
                "'\(name)' is not a valid feature name: use letters, digits and _, starting with a letter or _.")
        }
        if let other = part.features.first(where: { $0.name == name && $0.id != id }) {
            throw ToolError("Part \(part.name) already has a feature named '\(other.name)'.")
        }
    }
}

extension CADDocument {
    func partIndex(named name: String?) throws(ToolError) -> Int {
        let names = parts.map(\.name).joined(separator: ", ")
        guard let name else {
            switch parts.count {
            case 0: throw ToolError("The document has no parts.")
            case 1: return 0
            default: throw ToolError("The document has several parts (\(names)); say which one with 'part'.")
            }
        }
        guard let index = parts.firstIndex(where: { $0.name == name }) else {
            throw ToolError("No part named '\(name)'. Parts: \(names.isEmpty ? "none" : names).")
        }
        return index
    }

    func featureLocation(named name: String, part: String?) throws(ToolError) -> (part: Int, feature: Int) {
        let candidates =
            try part.map { (part) throws(ToolError) in [try partIndex(named: part)] } ?? Array(parts.indices)
        let matches = candidates.compactMap { index in
            parts[index].features.firstIndex { $0.name == name }.map { (part: index, feature: $0) }
        }
        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            let listing = candidates.map { index in
                let features = parts[index].features.map(\.name)
                return "\(parts[index].name): \(features.isEmpty ? "none" : features.joined(separator: ", "))"
            }
            throw ToolError("No feature named '\(name)'. Features by part: \(listing.joined(separator: "; ")).")
        default:
            let owners = matches.map { parts[$0.part].name }.joined(separator: ", ")
            throw ToolError("Several parts have a feature named '\(name)' (\(owners)); say which one with 'part'.")
        }
    }
}
