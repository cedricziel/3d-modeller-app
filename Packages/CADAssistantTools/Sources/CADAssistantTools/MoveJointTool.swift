import CADModel
import Foundation
import SwiftUIAssistant

public struct MoveJointTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "move_joint"

    public let description = """
        Drives a joint to a value: the angle of a revolute (degrees, from a's x axis to b's about a's z), or the \
        travel of a slider or cylindrical joint (mm along a's z). The value must lie within the joint's limits. The \
        rebuild then holds the joint there; free: true releases it again. Returns the joint's status, value and \
        remaining freedoms, and the instances it moved.
        """

    public var parameters: [ToolParameter] {
        [
            .string("joint", description: "The joint's name."),
            .custom(
                "value", description: "The angle in degrees or the travel in mm; a number or an expression.",
                required: false, schema: ToolSchemas.scalar),
            ToolParameter(
                name: "free", type: .boolean, description: "Release the joint instead of driving it.",
                required: false),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.moveJoint(arguments)
    }
}

extension CADSession {
    func moveJoint(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["joint", "value", "free"])
            let index = try document.jointIndex(named: try arguments.requiredString("joint"))
            var joint = document.joints[index]
            let value = try arguments.scalar("value")
            let free = try arguments.bool("free") ?? false
            guard (value != nil) != free else { throw ToolError("Give either value or free: true.") }
            guard let motion = joint.kind.motion else {
                throw ToolError(
                    "\(joint.name) is a \(joint.kind.rawValue) joint, which has no single motion; only revolute, "
                        + "slider and cylindrical joints move.")
            }
            let parameters = ParameterTable(document.parameters)
            let limits = JointDrive.evaluate(joint, parameters: parameters)
            if let value, limits.problem == nil, let number = try? parameters.evaluate(value),
                number < (limits.minimum ?? -.infinity) || number > (limits.maximum ?? .infinity)
            {
                throw ToolError(
                    "\(joint.name) moves within \(JointDrive.range(motion, limits.minimum, limits.maximum)); "
                        + "\(motion.format(number)) is outside.")
            }
            joint.value = value
            let drive = JointDrive.evaluate(joint, parameters: parameters)
            try JointArguments.checkDrive(joint, in: document)
            document.assembly?.joints[index] = joint
            let summary: String
            if let value, let number = drive.value {
                let shown = motion.format(number)
                summary =
                    if case .number = value { "Moved \(joint.name) to \(shown)" } else {
                        "Moved \(joint.name) to \(value) (\(shown))"
                    }
            } else {
                summary = "Released \(joint.name)"
            }
            return WriteFocus(actionName: "Move \(joint.name)", summary: summary, joint: joint.id)
        }
    }
}
