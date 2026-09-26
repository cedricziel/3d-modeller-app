import CADModel
import SwiftUIAssistant

public struct AddInstanceTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "add_instance"

    public let description = """
        Places a part in the assembly. The placement rotates the part by rotationDegrees (degrees) about \
        rotationAxis through the origin, then moves it by translation (mm); every number may be an expression over parameters. Without \
        'body' the instance shows every body of the part. Returns the instance's status and bounds, other \
        instances, and the changed listing lines.
        """

    public var parameters: [ToolParameter] {
        [
            .string("part", description: "The part to place."),
            .optionalString(
                "name",
                description: "Unique instance name (letters, digits, _). Defaults to the part name and a number."),
            .optionalString("body", description: "Place only this body of the part, such as Body2."),
            .custom("placement", description: "Where the part goes.", required: false, schema: ToolSchemas.placement),
            ToolParameter(
                name: "grounded", type: .boolean, description: "Fixed in place; defaults to false.", required: false),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.addInstance(arguments)
    }
}

public struct EditInstanceTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "edit_instance"

    public let description = """
        Moves, grounds or renames an instance. Placement fields left out keep their values, so \
        {"translation": {"z": 30}} changes only z. To place another part or body, delete the instance and add one.
        """

    public var parameters: [ToolParameter] {
        [
            .string("instance", description: "The instance's name."),
            .custom(
                "placement", description: "Placement fields to change.", required: false, schema: ToolSchemas.placement),
            ToolParameter(name: "grounded", type: .boolean, description: "Fixed in place or not.", required: false),
            .optionalString("new_name", description: "A new unique name."),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.editInstance(arguments)
    }
}

public struct DeleteInstanceTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "delete_instance"

    public let description = "Removes an instance from the assembly. The part stays."

    public var parameters: [ToolParameter] { [.string("instance", description: "The instance's name.")] }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.deleteInstance(arguments)
    }
}

extension CADSession {
    func addInstance(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let built = isResultCurrent ? result : nil
            let arguments = try Arguments(raw, allowed: ["part", "name", "body", "placement", "grounded"])
            let part = document.parts[try document.partIndex(named: try arguments.requiredString("part"))]
            let name =
                try arguments.string("name") ?? Naming.next(part.name, taken: Set(document.instances.map(\.name)))
            try Naming.checkInstanceName(name, in: document)
            let body = try arguments.string("body")
            if let body, let bodies = built?.parts.first(where: { $0.id == part.id })?.bodies.map(\.name),
                !bodies.contains(body)
            {
                let list = bodies.isEmpty ? "none" : bodies.joined(separator: ", ")
                throw ToolError("Part \(part.name) has no body named \(body). Bodies: \(list).")
            }
            let placement = try arguments.object("placement").map { (object) throws(ToolError) in
                try PlacementArguments(object).applied(to: .identity)
            }
            let instance = Instance(
                name: name, part: part.id, body: body, placement: placement ?? .identity,
                grounded: try arguments.bool("grounded") ?? false)
            document.assembly = Assembly(instances: document.instances + [instance])
            return WriteFocus(
                actionName: "Add instance \(name)", summary: "Added instance \(name) of part \(part.name)",
                instance: instance.id)
        }
    }

    func editInstance(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["instance", "placement", "grounded", "new_name"])
            let index = try document.instanceIndex(named: try arguments.requiredString("instance"))
            var instance = document.instances[index]
            let oldName = instance.name
            guard arguments.has("placement") || arguments.has("grounded") || arguments.has("new_name") else {
                throw ToolError("Give at least one of placement, grounded, new_name.")
            }
            if let object = try arguments.object("placement") {
                instance.placement = try PlacementArguments(object).applied(to: instance.placement)
            }
            if let grounded = try arguments.bool("grounded") { instance.grounded = grounded }
            if let newName = try arguments.string("new_name") {
                try Naming.checkInstanceName(newName, in: document, excluding: instance.id)
                instance.name = newName
            }
            document.assembly?.instances[index] = instance
            let summary =
                instance.name == oldName
                ? "Edited instance \(oldName)" : "Renamed instance \(oldName) to \(instance.name)"
            return WriteFocus(actionName: "Edit \(oldName)", summary: summary, instance: instance.id)
        }
    }

    func deleteInstance(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["instance"])
            let index = try document.instanceIndex(named: try arguments.requiredString("instance"))
            let instance = document.assembly?.instances.remove(at: index)
            let name = instance?.name ?? ""
            let removed = document.joints.filter { $0.a.instance == instance?.id || $0.b.instance == instance?.id }
            document.assembly?.joints.removeAll { joint in removed.contains { $0.id == joint.id } }
            let joints = removed.isEmpty ? "" : "; removed joints \(removed.map(\.name).joined(separator: ", "))"
            return WriteFocus(actionName: "Delete instance \(name)", summary: "Deleted instance \(name)\(joints)")
        }
    }
}
