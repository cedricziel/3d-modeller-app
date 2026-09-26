import Foundation

/// A folder of guidance the assistant loads on demand: `SKILL.md` and any other files next to it.
public struct Skill: Sendable, Equatable {
    public let name: String
    public let description: String
    /// `SKILL.md` without its frontmatter.
    public let body: String
    /// The folder's other files, relative to it, sorted.
    public let files: [String]
    public let directory: URL

    public init(name: String, description: String, body: String, files: [String], directory: URL) {
        self.name = name
        self.description = description
        self.body = body
        self.files = files
        self.directory = directory
    }
}

public enum SkillError: Error, Equatable, CustomStringConvertible {
    case unreadable(path: String)
    case missingSkillFile(folder: String)
    case missingFrontmatter(folder: String)
    case missingKey(folder: String, key: String)
    case nameMismatch(folder: String, name: String)

    public var description: String {
        switch self {
        case let .unreadable(path): "Cannot read \(path)."
        case let .missingSkillFile(folder): "Skill folder '\(folder)' has no SKILL.md."
        case let .missingFrontmatter(folder): "\(folder)/SKILL.md has no frontmatter block."
        case let .missingKey(folder, key): "\(folder)/SKILL.md has no '\(key)'."
        case let .nameMismatch(folder, name): "\(folder)/SKILL.md is named '\(name)'; it must match its folder."
        }
    }
}
