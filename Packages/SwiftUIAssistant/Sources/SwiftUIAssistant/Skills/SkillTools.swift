import Foundation

public struct ListSkillsTool: AssistantTool {
    let library: SkillLibrary

    public init(library: SkillLibrary) {
        self.library = library
    }

    public let name = "list_skills"

    public let description =
        "Lists the skills: guides for kinds of work, each with what it covers. Read one with get_skill."

    public func execute(arguments _: [String: JSONValue]) async throws -> ToolExecutionResult {
        .success(library.index)
    }
}

public struct GetSkillTool: AssistantTool {
    let library: SkillLibrary

    public init(library: SkillLibrary) {
        self.library = library
    }

    public let name = "get_skill"

    public let description = """
        Returns a skill's guide, followed by the other files in the skill, if any. With 'file', returns that file \
        instead.
        """

    public var parameters: [ToolParameter] {
        [
            .string("name", description: "The skill's name, as in the skill list."),
            .optionalString("file", description: "One of the files the guide lists, such as recipes.md."),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        guard case let .string(name) = arguments["name"] else { return .failure("'name' must be a skill name.") }
        guard let skill = library.skill(named: name) else {
            let names = library.skills.map(\.name).joined(separator: ", ")
            return .failure("No skill named '\(name)'. Skills: \(names).")
        }
        guard let fileArgument = arguments["file"], fileArgument != .null else {
            guard !skill.files.isEmpty else { return .success(skill.body) }
            return .success("\(skill.body)\nFiles: \(skill.files.joined(separator: ", "))")
        }
        guard case let .string(file) = fileArgument else {
            return .failure("'file' must be one of the skill's files.")
        }
        guard skill.files.contains(file) else {
            let listing =
                skill.files.isEmpty ? "It has no other files." : "Files: \(skill.files.joined(separator: ", "))"
            return .failure("Skill '\(name)' has no file '\(file)'. \(listing)")
        }
        guard let text = try? String(contentsOf: skill.directory.appending(path: file), encoding: .utf8) else {
            return .failure("\(file) in skill '\(name)' is not a text file.")
        }
        return .success(text)
    }
}
