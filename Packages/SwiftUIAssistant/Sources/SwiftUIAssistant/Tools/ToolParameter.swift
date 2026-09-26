import Foundation

/// Describes a parameter that a tool accepts
public struct ToolParameter: Sendable, Equatable {
    /// The name of the parameter
    public let name: String

    /// The type of the parameter
    public let type: ParameterType

    /// Human-readable description of the parameter
    public let description: String

    /// Whether this parameter is required
    public let required: Bool

    /// Allowed values for enum types
    public let enumValues: [String]?

    /// Default value if not provided
    public let defaultValue: JSONValue?

    /// A JSON Schema that replaces the one generated from `type` and `enumValues`
    public let schema: [String: JSONValue]?

    /// The data type of the parameter
    public enum ParameterType: String, Sendable, Equatable {
        case string
        case number
        case integer
        case boolean
        case array
        case object
    }

    public init(
        name: String,
        type: ParameterType,
        description: String,
        required: Bool = false,
        enumValues: [String]? = nil,
        defaultValue: JSONValue? = nil,
        schema: [String: JSONValue]? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.enumValues = enumValues
        self.defaultValue = defaultValue
        self.schema = schema
    }

    // MARK: - Schema Generation

    /// Generate a JSON Schema representation for this parameter
    public func toJSONSchema() -> [String: JSONValue] {
        if var schema {
            schema["description"] = .string(description)
            return schema
        }

        var schema: [String: JSONValue] = [
            "type": .string(type.rawValue),
            "description": .string(description),
        ]

        if let enumValues = enumValues {
            schema["enum"] = .array(enumValues.map { .string($0) })
        }

        return schema
    }
}

// MARK: - Convenience Initializers

public extension ToolParameter {
    /// Create a required string parameter
    static func string(_ name: String, description: String) -> ToolParameter {
        ToolParameter(name: name, type: .string, description: description, required: true)
    }

    /// Create an optional string parameter
    static func optionalString(_ name: String, description: String, defaultValue: String? = nil) -> ToolParameter {
        ToolParameter(
            name: name, type: .string, description: description, required: false,
            defaultValue: defaultValue.map { .string($0) })
    }

    /// Create a required number parameter
    static func number(_ name: String, description: String) -> ToolParameter {
        ToolParameter(name: name, type: .number, description: description, required: true)
    }

    /// Create an optional number parameter
    static func optionalNumber(_ name: String, description: String, defaultValue: Double? = nil) -> ToolParameter {
        ToolParameter(
            name: name, type: .number, description: description, required: false,
            defaultValue: defaultValue.map { .number($0) })
    }

    /// Create a required boolean parameter
    static func boolean(_ name: String, description: String) -> ToolParameter {
        ToolParameter(name: name, type: .boolean, description: description, required: true)
    }

    /// Create a parameter described by its own JSON Schema, for unions, nested objects and arrays
    static func custom(
        _ name: String, description: String, required: Bool = false, schema: [String: JSONValue]
    ) -> ToolParameter {
        ToolParameter(name: name, type: .object, description: description, required: required, schema: schema)
    }

    /// Create an enum parameter with allowed values
    static func enumParameter(_ name: String, description: String, values: [String], required: Bool = true)
        -> ToolParameter
    {
        ToolParameter(name: name, type: .string, description: description, required: required, enumValues: values)
    }
}
