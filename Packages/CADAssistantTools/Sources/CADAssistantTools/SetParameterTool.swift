import CADModel
import SwiftUIAssistant

public struct SetParameterTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "set_parameter"

    public let description = """
        Adds document parameters, changes their expressions, or removes them. Any numeric field of a feature can use \
        parameters by name. Lengths are in mm and angles in degrees. An expression is a number or arithmetic \
        (+ - * /, parentheses) over other parameters. Give one parameter with name and expression (or remove), or \
        several at once with 'parameters'; prefer one call with the list over one call per parameter. A list is one \
        undo step and its entries may refer to each other in any order. The change is refused as a whole when it \
        would make an expression that works now stop evaluating, for example by removing a parameter that features \
        still use.
        """

    public var parameters: [ToolParameter] {
        [
            .optionalString("name", description: "Parameter name: letters, digits and _, starting with a letter or _."),
            ToolSchemas.scalar("expression", "The new value. Leave out when removing."),
            ToolParameter(
                name: "remove", type: .boolean, description: "true to remove the parameter.", required: false),
            .custom(
                "parameters",
                description:
                    "Several parameters in one change instead of name: each {name, expression} or {name, remove: true}.",
                required: false,
                schema: [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"], "expression": .object(ToolSchemas.scalar),
                            "remove": ["type": "boolean"],
                        ],
                        "required": ["name"],
                        "additionalProperties": false,
                    ],
                ]),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.setParameter(arguments)
    }
}

extension CADSession {
    func setParameter(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["name", "expression", "remove", "parameters"])
            guard let list = try arguments.array("parameters") else {
                guard arguments.has("name") else {
                    throw ToolError("Give 'name' with 'expression' or 'remove', or a 'parameters' list.")
                }
                return try Self.applyParameter(arguments, to: &document)
            }
            let extra = ["name", "expression", "remove"].filter(arguments.has)
            guard extra.isEmpty else {
                throw ToolError("With 'parameters', leave out \(extra.map { "'\($0)'" }.joined(separator: ", ")).")
            }
            guard !list.isEmpty else {
                throw ToolError("'parameters' is empty; give at least one {name, expression} or {name, remove: true}.")
            }
            var seen: Set<String> = []
            var focus: WriteFocus?
            var changed = 0
            for (index, item) in list.enumerated() {
                guard let object = item.objectValue else {
                    throw ToolError(
                        "parameters[\(index)] must be an object such as {\"name\": \"width\", \"expression\": 60}.")
                }
                do throws(ToolError) {
                    let entry = try Arguments(object, allowed: ["name", "expression", "remove"])
                    let name = try entry.requiredString("name")
                    guard seen.insert(name).inserted else {
                        throw ToolError("'\(name)' is already in the list; give each parameter once.")
                    }
                    let previous = document.parameters
                    focus = try Self.applyParameter(entry, to: &document)
                    if document.parameters != previous { changed += 1 }
                } catch {
                    throw ToolError("parameters[\(index)]: \(error.description)")
                }
            }
            if list.count == 1, let focus { return focus }
            let summary =
                switch changed {
                case 0: "Changed no parameters"
                case list.count: "Changed \(changed) parameters"
                default: "Changed \(changed) of \(list.count) parameters"
                }
            return WriteFocus(actionName: "Set Parameters", summary: summary)
        }
    }

    private static func applyParameter(_ arguments: Arguments, to document: inout CADDocument) throws(ToolError)
        -> WriteFocus
    {
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
