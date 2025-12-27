import Foundation

/// A type-safe representation of JSON values that conforms to Sendable
public enum JSONValue: Sendable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    // MARK: - Convenience Initializers

    /// Create from any JSON-compatible value
    public init?(_ value: Any?) {
        guard let value = value else {
            self = .null
            return
        }

        switch value {
        case let string as String:
            self = .string(string)
        case let int as Int:
            self = .integer(int)
        case let double as Double:
            self = .number(double)
        case let float as Float:
            self = .number(Double(float))
        case let bool as Bool:
            self = .bool(bool)
        case let array as [Any]:
            var jsonArray: [JSONValue] = []
            for item in array {
                if let jsonItem = JSONValue(item) {
                    jsonArray.append(jsonItem)
                } else {
                    return nil
                }
            }
            self = .array(jsonArray)
        case let dict as [String: Any]:
            var jsonObject: [String: JSONValue] = [:]
            for (key, val) in dict {
                if let jsonVal = JSONValue(val) {
                    jsonObject[key] = jsonVal
                } else {
                    return nil
                }
            }
            self = .object(jsonObject)
        case is NSNull:
            self = .null
        default:
            return nil
        }
    }

    // MARK: - Value Extraction

    /// Convert back to Any for compatibility
    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .integer(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let values): return values.map { $0.anyValue }
        case .object(let values): return values.mapValues { $0.anyValue }
        }
    }

    /// Get as String if this is a string value
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Get as Double if this is a number value
    public var numberValue: Double? {
        switch self {
        case .number(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    /// Alias for numberValue
    public var doubleValue: Double? {
        numberValue
    }

    /// Get as Float if this is a number value
    public var floatValue: Float? {
        switch self {
        case .number(let value): return Float(value)
        case .integer(let value): return Float(value)
        default: return nil
        }
    }

    /// Get as Int if this is an integer value
    public var intValue: Int? {
        switch self {
        case .integer(let value): return value
        case .number(let value): return Int(exactly: value)
        default: return nil
        }
    }

    /// Get as Bool if this is a boolean value
    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Get as array if this is an array value
    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// Get as dictionary if this is an object value
    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Check if this is null
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: - Static Factory Methods

    /// Create JSONValue from any compatible value
    public static func fromAny(_ value: Any) -> JSONValue? {
        JSONValue(value)
    }

    // MARK: - Subscript Access

    /// Access array elements by index
    public subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self, index >= 0, index < array.count else {
            return nil
        }
        return array[index]
    }

    /// Access object values by key
    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else {
            return nil
        }
        return object[key]
    }
}

// MARK: - ExpressibleBy Literals

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .integer(int)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode JSON value")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - CustomStringConvertible

extension JSONValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .string(let value): return "\"\(value)\""
        case .number(let value): return String(value)
        case .integer(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return "null"
        case .array(let values): return "[\(values.map { $0.description }.joined(separator: ", "))]"
        case .object(let values):
            let pairs = values.map { "\"\($0.key)\": \($0.value.description)" }
            return "{\(pairs.joined(separator: ", "))}"
        }
    }
}

// MARK: - Dictionary Conversion Helpers

public extension Dictionary where Key == String, Value == JSONValue {
    /// Convert from [String: Any] dictionary
    init?(fromAny dict: [String: Any]) {
        var result: [String: JSONValue] = [:]
        for (key, value) in dict {
            guard let jsonValue = JSONValue(value) else {
                return nil
            }
            result[key] = jsonValue
        }
        self = result
    }

    /// Convert to [String: Any] dictionary
    var toAnyDict: [String: Any] {
        mapValues { $0.anyValue }
    }
}
