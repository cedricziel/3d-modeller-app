import SwiftUIAssistant

enum ToolSchemas {
    static let scalar: [String: JSONValue] = ["anyOf": [["type": "number"], ["type": "string"]]]

    static let vector: JSONValue = [
        "type": "object",
        "properties": ["x": .object(scalar), "y": .object(scalar), "z": .object(scalar)],
        "additionalProperties": false,
    ]

    static let placement: [String: JSONValue] = [
        "type": "object",
        "properties": ["translation": vector, "rotationAxis": vector, "rotationDegrees": .object(scalar)],
        "additionalProperties": false,
    ]

    static func scalar(_ name: String, _ description: String, required: Bool = false) -> ToolParameter {
        .custom(
            name, description: "\(description) A number or an expression over parameters, e.g. \"width / 2\".",
            required: required, schema: scalar)
    }

    static let featureName = ToolParameter.string("feature", description: "Name of the feature, as in the listing.")

    static let part = ToolParameter.optionalString(
        "part", description: "Name of the part. Needed only when the document has several parts.")
}
