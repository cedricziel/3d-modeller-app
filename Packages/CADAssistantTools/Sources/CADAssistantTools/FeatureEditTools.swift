import CADModel
import Foundation
import SwiftUIAssistant

public struct AddFeatureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "add_feature"

    public let description = """
        Adds a feature to a part: a solid (box, cylinder, sphere, cone, torus) with a placement and an operation, a \
        boolean that combines bodies, or a transform that moves a body. Lengths are in mm, angles in degrees; every \
        number may be an expression over parameters. The n-th feature that creates a new body in a part makes \
        Body<n>. It goes at the end of the part unless 'before' or 'after' names a feature. Returns the new \
        feature's status, status changes elsewhere, every body's validity, volume and bounds, and the changed \
        listing lines.
        """

    public var parameters: [ToolParameter] {
        [
            ToolSchemas.part,
            .optionalString(
                "name",
                description:
                    "Unique name in the part (letters, digits, _). Defaults to the type and a number, e.g. Box2."),
            .optionalString("before", description: "Insert before this feature."),
            .optionalString("after", description: "Insert after this feature."),
        ] + ToolSchemas.kindParameters(typeRequired: true)
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.addFeature(arguments)
    }
}

public struct EditFeatureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "edit_feature"

    public let description = """
        Changes fields of an existing feature; fields left out keep their values, including each placement value. \
        Lengths are in mm, angles in degrees; every number may be an expression over parameters. Changing the type \
        keeps the dimensions both types share. Returns the feature's status, status changes elsewhere, every body's \
        validity, volume and bounds, and the changed listing lines. Use rename_feature to rename.
        """

    public var parameters: [ToolParameter] {
        [ToolSchemas.featureName, ToolSchemas.part] + ToolSchemas.kindParameters(typeRequired: false)
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.editFeature(arguments)
    }
}

extension CADSession {
    func addFeature(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["part", "name", "before", "after"] + FeatureSpec.keys)
            let partIndex = try document.partIndex(named: try arguments.string("part"))
            let given = try FeatureSpec(arguments)
            let kind = try given.kind(given: given)
            let part = document.parts[partIndex]
            let name = try arguments.string("name") ?? Self.defaultName(for: given.type ?? "", in: part)
            try Naming.checkFeatureName(name, in: part)
            var index = part.features.endIndex
            switch (try arguments.string("before"), try arguments.string("after")) {
            case (nil, nil): break
            case (let before?, nil): index = try Self.index(of: before, in: part)
            case (nil, let after?): index = try Self.index(of: after, in: part) + 1
            case (_?, _?): throw ToolError("Give 'before' or 'after', not both.")
            }
            let feature = Feature(name: name, kind: kind)
            document.parts[partIndex].features.insert(feature, at: index)
            return WriteFocus(
                actionName: "Add \(name)", summary: "Added \(name) to part \(part.name)", feature: feature.id)
        }
    }

    func editFeature(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["feature", "part"] + FeatureSpec.keys)
            let location = try document.featureLocation(
                named: try arguments.requiredString("feature"), part: try arguments.string("part"))
            let feature = document.parts[location.part].features[location.feature]
            let given = try FeatureSpec(arguments)
            guard !given.isEmpty else {
                throw ToolError("Give at least one field to change: \(FeatureSpec.keys.joined(separator: ", ")).")
            }
            let kind = try given.overriding(FeatureSpec(feature.kind)).kind(given: given)
            document.parts[location.part].features[location.feature].kind = kind
            return WriteFocus(
                actionName: "Edit \(feature.name)", summary: "Edited \(feature.name)", feature: feature.id)
        }
    }

    private static func index(of name: String, in part: Part) throws(ToolError) -> Int {
        guard let index = part.features.firstIndex(where: { $0.name == name }) else {
            throw ToolError("No feature named '\(name)' in part \(part.name).")
        }
        return index
    }

    private static func defaultName(for type: String, in part: Part) -> String {
        let base = type.prefix(1).uppercased() + type.dropFirst()
        let names = Set(part.features.map(\.name))
        return (1...).lazy.map { "\(base)\($0)" }.first { !names.contains($0) }!
    }
}
