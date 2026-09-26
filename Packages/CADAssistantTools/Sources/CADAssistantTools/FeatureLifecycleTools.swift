import SwiftUIAssistant

public struct DeleteFeatureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "delete_feature"

    public let description = """
        Deletes a feature. Deleting a feature that creates a body renumbers later bodies; references to them are \
        updated to match and reported. The delete is refused while another feature uses the deleted feature's body. \
        Returns status changes, every body's validity, volume and bounds, and the changed listing lines.
        """

    public var parameters: [ToolParameter] { [ToolSchemas.featureName, ToolSchemas.part] }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.deleteFeature(arguments)
    }
}

public struct RenameFeatureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "rename_feature"

    public let description = "Renames a feature. Names are unique within a part: letters, digits and _."

    public var parameters: [ToolParameter] {
        [ToolSchemas.featureName, .string("new_name", description: "The new name."), ToolSchemas.part]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.renameFeature(arguments)
    }
}

public struct SuppressFeatureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "suppress_feature"

    public let description = """
        Suppresses a feature so the rebuild skips it, or brings it back with suppressed: false. A suppressed \
        feature keeps its body number; features that use its body are skipped. Returns status changes, every \
        body's validity, volume and bounds, and the changed listing lines.
        """

    public var parameters: [ToolParameter] {
        [
            ToolSchemas.featureName,
            ToolParameter(
                name: "suppressed", type: .boolean, description: "false to unsuppress. Defaults to true.",
                required: false),
            ToolSchemas.part,
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.suppressFeature(arguments)
    }
}

extension CADSession {
    func deleteFeature(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["feature", "part"])
            let location = try document.featureLocation(
                named: try arguments.requiredString("feature"), part: try arguments.string("part"))
            let feature = document.parts[location.part].features.remove(at: location.feature)
            return WriteFocus(
                actionName: "Delete \(feature.name)",
                summary: "Deleted \(feature.name) from part \(document.parts[location.part].name)")
        }
    }

    func renameFeature(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["feature", "new_name", "part"])
            let location = try document.featureLocation(
                named: try arguments.requiredString("feature"), part: try arguments.string("part"))
            let feature = document.parts[location.part].features[location.feature]
            let newName = try arguments.requiredString("new_name")
            try Naming.checkFeatureName(newName, in: document.parts[location.part], excluding: feature.id)
            document.parts[location.part].features[location.feature].name = newName
            return WriteFocus(
                actionName: "Rename \(feature.name) to \(newName)", summary: "Renamed \(feature.name) to \(newName)",
                feature: feature.id)
        }
    }

    func suppressFeature(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["feature", "suppressed", "part"])
            let location = try document.featureLocation(
                named: try arguments.requiredString("feature"), part: try arguments.string("part"))
            let feature = document.parts[location.part].features[location.feature]
            let suppressed = try arguments.bool("suppressed") ?? true
            document.parts[location.part].features[location.feature].suppressed = suppressed
            let verb = suppressed ? "Suppress" : "Unsuppress"
            return WriteFocus(
                actionName: "\(verb) \(feature.name)", summary: "\(verb)ed \(feature.name)", feature: feature.id)
        }
    }
}
