import CADModel
import SwiftUIAssistant

public struct SetParameterTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "set_parameter"

    public let description = """
        Adds a document parameter, changes its expression, or removes it. Any numeric field of a feature can use \
        parameters by name. Lengths are in mm and angles in degrees. An expression is a number or arithmetic \
        (+ - * /, parentheses) over other parameters. The change is refused when it would make an expression that \
        works now stop evaluating, for example by removing a parameter that features still use.
        """

    public var parameters: [ToolParameter] {
        [
            .string("name", description: "Parameter name: letters, digits and _, starting with a letter or _."),
            ToolSchemas.scalar("expression", "The new value. Leave out when removing."),
            ToolParameter(
                name: "remove", type: .boolean, description: "true to remove the parameter.", required: false),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.setParameter(arguments)
    }
}

extension CADSession {
    func setParameter(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["name", "expression", "remove"])
            let name = try arguments.requiredString("name")
            let expression = try arguments.scalar("expression")
            let exists = document.parameters.contains { $0.name == name }
            if try arguments.bool("remove") == true {
                guard expression == nil else { throw ToolError("Give either 'expression' or 'remove', not both.") }
                guard exists else {
                    let names = document.parameters.map(\.name)
                    throw ToolError(
                        "No parameter named '\(name)'. Parameters: \(names.isEmpty ? "none" : names.joined(separator: ", "))."
                    )
                }
                document.parameters.removeAll { $0.name == name }
                return WriteFocus(actionName: "Remove Parameter \(name)", summary: "Removed parameter \(name)")
            }
            guard let expression else { throw ToolError("Give 'expression' to set the parameter, or 'remove': true.") }
            if exists {
                for index in document.parameters.indices where document.parameters[index].name == name {
                    document.parameters[index].expression = expression
                }
                return WriteFocus(actionName: "Set Parameter \(name)", summary: "Set parameter \(name) = \(expression)")
            }
            guard Naming.isIdentifier(name) else {
                throw ToolError(
                    "'\(name)' is not a valid parameter name: use letters, digits and _, starting with a letter or _.")
            }
            document.parameters.append(Parameter(name: name, expression: expression))
            return WriteFocus(actionName: "Add Parameter \(name)", summary: "Added parameter \(name) = \(expression)")
        }
    }
}
