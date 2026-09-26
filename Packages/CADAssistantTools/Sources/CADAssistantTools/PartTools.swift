import CADModel
import SwiftUIAssistant

public struct AddPartTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "add_part"

    public let description = """
        Adds an empty part with its own feature tree. Give 'part' to add_feature and the other feature tools to \
        build it. A part sits at the origin in its own coordinates; place it in the assembly with add_instance.
        """

    public var parameters: [ToolParameter] {
        [
            .optionalString(
                "name", description: "Unique part name (letters, digits, _). Defaults to Part<n>.")
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.addPart(arguments)
    }
}

public struct RenamePartTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "rename_part"

    public let description = "Renames a part. Instances keep placing it."

    public var parameters: [ToolParameter] {
        [
            .string("part", description: "The part's current name."),
            .string("new_name", description: "The new name (letters, digits, _), unique among parts."),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.renamePart(arguments)
    }
}

public struct DeletePartTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "delete_part"

    public let description = """
        Deletes a part and its features. Refused while instances place the part, and for the only part.
        """

    public var parameters: [ToolParameter] { [.string("part", description: "The part to delete.")] }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.deletePart(arguments)
    }
}

extension CADSession {
    func addPart(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["name"])
            let name = try arguments.string("name") ?? Naming.next("Part", taken: Set(document.parts.map(\.name)))
            try Naming.checkPartName(name, in: document)
            document.parts.append(Part(name: name))
            return WriteFocus(actionName: "Add part \(name)", summary: "Added part \(name)")
        }
    }

    func renamePart(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["part", "new_name"])
            let index = try document.partIndex(named: try arguments.requiredString("part"))
            let old = document.parts[index]
            let newName = try arguments.requiredString("new_name")
            try Naming.checkPartName(newName, in: document, excluding: old.id)
            document.parts[index].name = newName
            return WriteFocus(
                actionName: "Rename part \(old.name) to \(newName)", summary: "Renamed part \(old.name) to \(newName)")
        }
    }

    func deletePart(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["part"])
            let index = try document.partIndex(named: try arguments.requiredString("part"))
            let part = document.parts[index]
            guard document.parts.count > 1 else {
                throw ToolError("\(part.name) is the only part; a document keeps at least one.")
            }
            let users = document.instances.filter { $0.part == part.id }.map(\.name)
            guard users.isEmpty else {
                throw ToolError(
                    "Part \(part.name) is placed by instances \(users.joined(separator: ", ")); delete them first.")
            }
            document.parts.remove(at: index)
            return WriteFocus(actionName: "Delete part \(part.name)", summary: "Deleted part \(part.name)")
        }
    }
}
