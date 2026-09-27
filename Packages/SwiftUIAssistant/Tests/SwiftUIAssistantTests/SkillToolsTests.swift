import Foundation
@testable import SwiftUIAssistant
import Testing

@Suite("list_skills and get_skill")
struct SkillToolsTests {
    private func library() throws -> SkillLibrary {
        let root = FileManager.default.temporaryDirectory.appending(path: "skills-\(UUID().uuidString)")
        let files: [String: Data] = [
            "joints/SKILL.md": Data("---\nname: joints\ndescription: Joints.\n---\n# Joints\nUse add_joint.\n".utf8),
            "joints/recipes.md": Data("Lid on a box.\n".utf8),
            "joints/reference/limits.md": Data("Limits.\n".utf8),
            "joints/binary.bin": Data([0xFF, 0xFE, 0x00, 0xC3]),
            "sketches/SKILL.md": Data("---\nname: sketches\ndescription: Sketches.\n---\nSketch.\n".utf8),
        ]
        for (path, data) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
        return try SkillLibrary(directory: root)
    }

    @Test("list_skills returns the index")
    func listSkills() async throws {
        let result = try await ListSkillsTool(library: library()).execute(arguments: [:])
        #expect(result.success)
        #expect(result.message == "- joints: Joints.\n- sketches: Sketches.")
    }

    @Test("get_skill returns the body and lists the other files")
    func body() async throws {
        let tool = try GetSkillTool(library: library())
        let joints = try await tool.execute(arguments: ["name": "joints"])
        #expect(joints.success)
        #expect(joints.message == "# Joints\nUse add_joint.\n\nFiles: binary.bin, recipes.md, reference/limits.md")
        let sketches = try await tool.execute(arguments: ["name": "sketches"])
        #expect(sketches.message == "Sketch.\n")
    }

    @Test("get_skill with a file returns that file, also from a subfolder")
    func file() async throws {
        let tool = try GetSkillTool(library: library())
        let recipes = try await tool.execute(arguments: ["name": "joints", "file": "recipes.md"])
        #expect(recipes.message == "Lid on a box.\n")
        let limits = try await tool.execute(arguments: ["name": "joints", "file": "reference/limits.md"])
        #expect(limits.message == "Limits.\n")
    }

    @Test("An unknown skill is refused with the available names")
    func unknownSkill() async throws {
        let result = try await GetSkillTool(library: library()).execute(arguments: ["name": "gears"])
        #expect(!result.success)
        #expect(result.message == "No skill named 'gears'. Skills: joints, sketches.")
    }

    @Test("A missing name is refused")
    func missingName() async throws {
        let result = try await GetSkillTool(library: library()).execute(arguments: [:])
        #expect(!result.success)
        #expect(result.message == "'name' must be a skill name.")
    }

    @Test("A non-string file argument is refused, but an absent or null one returns the body")
    func nonStringFile() async throws {
        let tool = try GetSkillTool(library: library())
        let result = try await tool.execute(arguments: ["name": "joints", "file": 5])
        #expect(!result.success)
        #expect(result.message == "'file' must be one of the skill's files.")
        let absent = try await tool.execute(arguments: ["name": "sketches"])
        #expect(absent.message == "Sketch.\n")
        let null = try await tool.execute(arguments: ["name": "sketches", "file": .null])
        #expect(null.message == "Sketch.\n")
    }

    @Test(
        "Files outside the skill's list are refused",
        arguments: ["nope.md", "../sketches/SKILL.md", "/etc/passwd", "SKILL.md"]
    )
    func unlistedFile(file: String) async throws {
        let tool = try GetSkillTool(library: library())
        let result = try await tool.execute(arguments: ["name": "joints", "file": .string(file)])
        #expect(!result.success)
        let expected = "Skill 'joints' has no file '\(file)'. Files: binary.bin, recipes.md, reference/limits.md"
        #expect(result.message == expected)
    }

    @Test("A skill without other files says so when a file is asked for")
    func noFiles() async throws {
        let result = try await GetSkillTool(library: library()).execute(arguments: ["name": "sketches", "file": "x.md"])
        #expect(result.message == "Skill 'sketches' has no file 'x.md'. It has no other files.")
    }

    @Test("A file that is not UTF-8 text is refused")
    func binary() async throws {
        let tool = try GetSkillTool(library: library())
        let result = try await tool.execute(arguments: ["name": "joints", "file": "binary.bin"])
        #expect(!result.success)
        #expect(result.message == "binary.bin in skill 'joints' is not a text file.")
    }
}
