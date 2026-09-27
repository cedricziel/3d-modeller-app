import Foundation

/// The skills in the subfolders of one directory.
public struct SkillLibrary: Sendable {
    public let skills: [Skill]

    public init(directory: URL) throws(SkillError) {
        let manager = FileManager.default
        let folders: [URL]
        do {
            folders = try manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
            )
        } catch {
            throw .unreadable(path: directory.path)
        }
        var skills: [Skill] = []
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            try skills.append(Self.load(folder))
        }
        self.skills = skills.sorted { $0.name < $1.name }
    }

    public func skill(named name: String) -> Skill? {
        skills.first { $0.name == name }
    }

    /// One line per skill, `- name: description`, for the system prompt.
    public var index: String {
        skills.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
    }

    private static func load(_ folder: URL) throws(SkillError) -> Skill {
        let folderName = folder.lastPathComponent
        let skillFile = folder.appending(path: "SKILL.md")
        guard FileManager.default.fileExists(atPath: skillFile.path) else {
            throw .missingSkillFile(folder: folderName)
        }
        guard let text = try? String(contentsOf: skillFile, encoding: .utf8) else {
            throw .unreadable(path: skillFile.path)
        }
        guard let parsed = Frontmatter.parse(text) else { throw .missingFrontmatter(folder: folderName) }
        let fields = parsed.fields
        guard let name = fields["name"], !name.isEmpty else { throw .missingKey(folder: folderName, key: "name") }
        guard let description = fields["description"], !description.isEmpty else {
            throw .missingKey(folder: folderName, key: "description")
        }
        guard name == folderName else { throw .nameMismatch(folder: folderName, name: name) }
        return Skill(
            name: name, description: description, body: parsed.body, files: files(in: folder), directory: folder
        )
    }

    private static func files(in folder: URL) -> [String] {
        let base = folder.resolvingSymlinksInPath().path + "/"
        let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles
        )
        var files: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(base.count))
            if path != "SKILL.md" {
                files.append(path)
            }
        }
        return files.sorted()
    }
}
