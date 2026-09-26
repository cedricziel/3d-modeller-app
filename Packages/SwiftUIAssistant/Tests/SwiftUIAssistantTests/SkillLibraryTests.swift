import Foundation
@testable import SwiftUIAssistant
import Testing

@Suite("Skill library")
struct SkillLibraryTests {
    /// A fresh temporary skills directory holding `files` (relative path → contents).
    private func directory(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "skills-\(UUID().uuidString)")
        for (path, contents) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: url)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func skillFile(_ name: String, _ description: String, _ body: String = "Body.") -> String {
        "---\nname: \(name)\ndescription: \(description)\n---\n\(body)\n"
    }

    @Test("Frontmatter gives the fields and the body after the closing line")
    func frontmatter() throws {
        let parsed = try #require(Frontmatter.parse("---\nname: a\ndescription: Does a.\nextra: x\n---\n\n# A\nText\n"))
        #expect(parsed.fields == ["name": "a", "description": "Does a.", "extra": "x"])
        #expect(parsed.body == "# A\nText\n")
    }

    @Test("Frontmatter keeps everything after the first colon and accepts CRLF line endings")
    func frontmatterColonAndCRLF() throws {
        let parsed = try #require(
            Frontmatter.parse("---\r\nname: a\r\ndescription: Load before: add_joint\r\n---\r\nBody\r\n"))
        #expect(parsed.fields["description"] == "Load before: add_joint")
        #expect(parsed.body == "Body\n")
    }

    @Test("Text without an opening or closing line has no frontmatter")
    func noFrontmatter() {
        #expect(Frontmatter.parse("# Title\n") == nil)
        #expect(Frontmatter.parse("---\nname: a\n") == nil)
    }

    @Test("Skills load sorted by name with their other files, skipping hidden ones")
    func loads() throws {
        let root = try directory([
            "joints/SKILL.md": skillFile("joints", "Joints.", "# Joints"),
            "joints/recipes.md": "Recipes",
            "joints/reference/limits.md": "Limits",
            "joints/.DS_Store": "x",
            "sketches/SKILL.md": skillFile("sketches", "Sketches."),
        ])
        let library = try SkillLibrary(directory: root)
        #expect(library.skills.map(\.name) == ["joints", "sketches"])
        let joints = try #require(library.skill(named: "joints"))
        #expect(joints.description == "Joints.")
        #expect(joints.body == "# Joints\n")
        #expect(joints.files == ["recipes.md", "reference/limits.md"])
        #expect(library.skill(named: "sketches")?.files == [])
        #expect(library.skill(named: "nope") == nil)
        #expect(library.index == "- joints: Joints.\n- sketches: Sketches.")
    }

    @Test("A folder without SKILL.md is refused")
    func missingSkillFile() throws {
        let root = try directory(["a/notes.md": "x"])
        #expect(throws: SkillError.missingSkillFile(folder: "a")) { try SkillLibrary(directory: root) }
    }

    @Test("A SKILL.md without frontmatter is refused")
    func missingFrontmatter() throws {
        let root = try directory(["a/SKILL.md": "# A\n"])
        #expect(throws: SkillError.missingFrontmatter(folder: "a")) { try SkillLibrary(directory: root) }
    }

    @Test("A SKILL.md without a description is refused")
    func missingKey() throws {
        let root = try directory(["a/SKILL.md": "---\nname: a\n---\nBody\n"])
        #expect(throws: SkillError.missingKey(folder: "a", key: "description")) { try SkillLibrary(directory: root) }
    }

    @Test("A name that differs from the folder is refused")
    func nameMismatch() throws {
        let root = try directory(["a/SKILL.md": skillFile("b", "B.")])
        #expect(throws: SkillError.nameMismatch(folder: "a", name: "b")) { try SkillLibrary(directory: root) }
    }

    @Test("A directory that does not exist is refused")
    func unreadable() {
        let root = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)")
        #expect(throws: SkillError.unreadable(path: root.path)) { try SkillLibrary(directory: root) }
    }
}
