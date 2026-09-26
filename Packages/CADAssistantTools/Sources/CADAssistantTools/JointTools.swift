import Foundation
import CADModel
import SwiftUIAssistant

public struct AddJointTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "add_joint"

    public let description = """
        Joins two instances by frames on their faces; every rebuild solves the joints and moves the instances that \
        are not grounded. Side b's frame is turned half a turn so the two faces meet flush (outward normals facing \
        each other); flip: true keeps them pointing the same way. Kinds: fixed (frames coincide), revolute (turns \
        about z), slider (slides along z, no turning), cylindrical (slides along and turns about z), ball (origins \
        meet, turns freely), planar (b stays in a's face plane, slides and turns in it). A side's offset moves its \
        frame in mm and turns it in degrees. Returns each joint's status, the instances it moved and the changed \
        listing lines.
        """

    public var parameters: [ToolParameter] {
        [
            .string("kind", description: "fixed, revolute, slider, cylindrical, ball or planar."),
            .custom(
                "a", description: "The first frame; its instance usually stays.", required: true,
                schema: JointArguments.sideSchema),
            .custom(
                "b", description: "The second frame; its instance moves onto a's.", required: true,
                schema: JointArguments.sideSchema),
            .optionalString(
                "name", description: "Unique joint name. Defaults to the kind and a number, such as Fixed1."),
            ToolParameter(
                name: "flip", type: .boolean, description: "Keep b's frame unturned; defaults to false.",
                required: false),
            .custom(
                "limits", description: JointArguments.limitsDescription, required: false,
                schema: JointArguments.limitsSchema),
            .custom(
                "value",
                description: "Drives the joint to this angle (revolute, degrees) or travel (slider, cylindrical, mm).",
                required: false, schema: ToolSchemas.scalar),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.addJoint(arguments)
    }
}

public struct EditJointTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "edit_joint"

    public let description = """
        Changes a joint's kind, replaces a whole side (a or b), flips it, sets its limits or renames it. Fields \
        left out keep their values. A new kind drops a value and limits that do not fit it. Use move_joint to drive it.
        """

    public var parameters: [ToolParameter] {
        [
            .string("joint", description: "The joint's name."),
            .optionalString("kind", description: "fixed, revolute, slider, cylindrical, ball or planar."),
            .custom("a", description: "A new first frame.", required: false, schema: JointArguments.sideSchema),
            .custom("b", description: "A new second frame.", required: false, schema: JointArguments.sideSchema),
            ToolParameter(name: "flip", type: .boolean, description: "Keep b's frame unturned.", required: false),
            .custom(
                "limits", description: JointArguments.limitsDescription + " {} removes them.", required: false,
                schema: JointArguments.limitsSchema),
            .optionalString("new_name", description: "A new unique name."),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.editJoint(arguments)
    }
}

public struct DeleteJointTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "delete_joint"

    public let description = "Removes a joint. Its instances go back to their placements unless other joints hold them."

    public var parameters: [ToolParameter] { [.string("joint", description: "The joint's name.")] }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.deleteJoint(arguments)
    }
}

extension CADSession {
    func addJoint(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let built = isResultCurrent ? result : nil
            let arguments = try Arguments(raw, allowed: ["kind", "a", "b", "name", "flip", "limits", "value"])
            let kind = try JointArguments.kind(try arguments.requiredString("kind"))
            let (a, b) = try sides(arguments, in: document, result: built, required: true)
            let base = kind.rawValue.prefix(1).uppercased() + kind.rawValue.dropFirst()
            let name = try arguments.string("name") ?? Naming.next(base, taken: Set(document.joints.map(\.name)))
            try Naming.checkJointName(name, in: document)
            let joint = Joint(
                name: name, kind: kind, a: a!, b: b!, flip: try arguments.bool("flip") ?? false,
                limits: try arguments.object("limits").flatMap { (object) throws(ToolError) in
                    try JointArguments.limits(object)
                },
                value: try arguments.scalar("value"))
            try Self.checkInstances(joint, in: document)
            try JointArguments.checkDrive(joint, in: document)
            if document.assembly == nil { document.assembly = Assembly() }
            document.assembly?.joints.append(joint)
            return WriteFocus(
                actionName: "Add joint \(name)", summary: "Added \(kind.rawValue) joint \(name)", joint: joint.id)
        }
    }

    func editJoint(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let built = isResultCurrent ? result : nil
            let arguments = try Arguments(raw, allowed: ["joint", "kind", "a", "b", "flip", "limits", "new_name"])
            let index = try document.jointIndex(named: try arguments.requiredString("joint"))
            var joint = document.joints[index]
            let oldName = joint.name
            guard !arguments.keys.subtracting(["joint"]).isEmpty else {
                throw ToolError("Give at least one of kind, a, b, flip, limits, new_name.")
            }
            var dropped: String?
            if let kind = try arguments.string("kind") {
                let old = joint.kind
                joint.kind = try JointArguments.kind(kind)
                dropped = JointArguments.dropMismatchedDrive(&joint, from: old)
            }
            if let limits = try arguments.object("limits") { joint.limits = try JointArguments.limits(limits) }
            let (a, b) = try sides(arguments, in: document, result: built, required: false)
            if let a { joint.a = a }
            if let b { joint.b = b }
            if let flip = try arguments.bool("flip") { joint.flip = flip }
            if let newName = try arguments.string("new_name") {
                try Naming.checkJointName(newName, in: document, excluding: joint.id)
                joint.name = newName
            }
            try Self.checkInstances(joint, in: document)
            try JointArguments.checkDrive(joint, in: document)
            document.assembly?.joints[index] = joint
            let summary =
                (joint.name == oldName ? "Edited joint \(oldName)" : "Renamed joint \(oldName) to \(joint.name)")
                + (dropped.map { "; \($0)" } ?? "")
            return WriteFocus(actionName: "Edit \(oldName)", summary: summary, joint: joint.id)
        }
    }

    func deleteJoint(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["joint"])
            let index = try document.jointIndex(named: try arguments.requiredString("joint"))
            let joint = document.assembly?.joints.remove(at: index)
            let name = joint?.name ?? ""
            return WriteFocus(actionName: "Delete joint \(name)", summary: "Deleted joint \(name)")
        }
    }

    private func sides(
        _ arguments: Arguments, in document: CADDocument, result: RebuildResult?, required: Bool
    ) throws(ToolError) -> (JointFrameRef?, JointFrameRef?) {
        func side(_ key: String) throws(ToolError) -> JointFrameRef? {
            guard let object = try arguments.object(key) else {
                if required { throw ToolError("Missing required argument '\(key)'.") }
                return nil
            }
            return try JointArguments.side(object, key, in: document, result: result)
        }
        return (try side("a"), try side("b"))
    }

    private static func checkInstances(_ joint: Joint, in document: CADDocument) throws(ToolError) {
        guard joint.a.instance != joint.b.instance else {
            let name = document.instances.first { $0.id == joint.a.instance }?.name ?? "one instance"
            throw ToolError("Both sides are on \(name); a joint joins two instances.")
        }
    }
}

extension Naming {
    static func checkJointName(_ name: String, in document: CADDocument, excluding id: UUID? = nil) throws(ToolError) {
        guard isIdentifier(name) else {
            throw ToolError(
                "'\(name)' is not a valid joint name: use letters, digits and _, starting with a letter or _.")
        }
        if document.joints.contains(where: { $0.name == name && $0.id != id }) {
            throw ToolError("A joint named \(name) already exists.")
        }
    }
}
