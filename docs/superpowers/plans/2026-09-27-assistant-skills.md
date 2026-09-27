# Assistant Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the modelling assistant load skills (folders with a `SKILL.md`) through `list_skills` and `get_skill`, and move the Sketches, Parts and assemblies, and Joints/Motion sections of the system prompt into three bundled skills.

**Architecture:** Generic skill loading and the two tools live in SwiftUIAssistant (`Skill`, `SkillLibrary`, `ListSkillsTool`, `GetSkillTool`). CADAssistantTools bundles the CAD skills as a copied resource folder, loads them once in `CADSkills.library`, registers the tools in `CADTools.all`, and builds `CADAssistantPrompt.system` from the core prompt plus a generated skill index.

**Tech Stack:** Swift 6, Swift Package Manager resources (`.copy`), Swift Testing, Foundation `FileManager`.

**Spec:** `docs/superpowers/specs/2026-09-27-assistant-skills-design.md`

## Global Constraints

- Build and test with `xcrun swift build` / `xcrun swift test`, never bare `swift`.
- Swift 6 strict concurrency; macOS 26.0 deployment target.
- A skill is a folder `<name>/SKILL.md` with frontmatter `name` and `description` (both required, one line each); `name` equals the folder name; other keys are ignored; no YAML dependency.
- Nothing in a skill is executed.
- The skills folder is added with `.copy("Resources/Skills")`, not `.process`.
- The moved prompt sections are moved word for word.
- `get_skill` with `file` returns only files in the skill's `files` list, and only UTF-8 text.
- Commits are semantic (`feat(assistant): …`, `test(…)`, `docs(…)`); no code comments unless one earns its place; match surrounding style (4-space indent, 120 columns).

## Review Focus

- A `SKILL.md` saved with CRLF line endings must load like an LF one (test in Task 1).
- A `description` containing a colon ("Load before: add_joint") must keep everything after the first colon (test in Task 1).
- Finder litter (`.DS_Store`) in a skill folder must not show up in `files` (test in Task 1).
- A file in a subfolder of a skill (`reference/x.md`) must be listed and readable by its relative path (tests in Tasks 1 and 2).
- The app bundle must actually contain the skills folder; a missing folder is a `fatalError` at first prompt use (bundle check in Task 5).

Note on the spec: it lists "two skills with the same name" as a load error. Since `name` must equal the folder name and folder names in one directory are unique, that case cannot occur once the name check exists, so there is no separate error for it.

---

### Task 1: `Skill`, frontmatter parsing and `SkillLibrary`

**Files:**

- Create: `Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Skills/Skill.swift`
- Create: `Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Skills/SkillLibrary.swift`
- Create: `Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Skills/Frontmatter.swift`
- Test: `Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/SkillLibraryTests.swift`

**Interfaces:**

- Produces:
  - `public struct Skill: Sendable, Equatable { name: String; description: String; body: String; files: [String]; directory: URL }`
  - `public enum SkillError: Error, Equatable, CustomStringConvertible { case unreadable(path: String); case missingSkillFile(folder: String); case missingFrontmatter(folder: String); case missingKey(folder: String, key: String); case nameMismatch(folder: String, name: String) }`
  - `public struct SkillLibrary: Sendable { public let skills: [Skill]; public init(directory: URL) throws(SkillError); public func skill(named: String) -> Skill?; public var index: String }`
  - `enum Frontmatter { static func parse(_ text: String) -> (fields: [String: String], body: String)? }` (internal)

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import SwiftUIAssistant

@Suite("Skill library")
struct SkillLibraryTests {
    /// A fresh temporary skills directory holding `files` (relative path → contents).
    private func directory(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "skills-\(UUID().uuidString)")
        for (path, contents) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
        let parsed = try #require(Frontmatter.parse("---\r\nname: a\r\ndescription: Load before: add_joint\r\n---\r\nBody\r\n"))
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/SwiftUIAssistant && xcrun swift test --filter SkillLibraryTests`
Expected: build failure, `cannot find 'Frontmatter' in scope` / `cannot find 'SkillLibrary' in scope`.

- [ ] **Step 3: Implement**

`Skills/Frontmatter.swift`:

```swift
enum Frontmatter {
    /// The `key: value` lines between an opening and a closing `---` line, and the text after them.
    static func parse(_ text: String) -> (fields: [String: String], body: String)? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (fields, String(body.drop { $0 == "\n" }))
    }
}
```

`Skills/Skill.swift`:

```swift
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
        case .unreadable(let path): "Cannot read \(path)."
        case .missingSkillFile(let folder): "Skill folder '\(folder)' has no SKILL.md."
        case .missingFrontmatter(let folder): "\(folder)/SKILL.md has no frontmatter block."
        case .missingKey(let folder, let key): "\(folder)/SKILL.md has no '\(key)'."
        case .nameMismatch(let folder, let name): "\(folder)/SKILL.md is named '\(name)'; it must match its folder."
        }
    }
}
```

`Skills/SkillLibrary.swift`:

```swift
import Foundation

/// The skills in the subfolders of one directory.
public struct SkillLibrary: Sendable {
    public let skills: [Skill]

    public init(directory: URL) throws(SkillError) {
        let manager = FileManager.default
        let folders: [URL]
        do {
            folders = try manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        } catch {
            throw .unreadable(path: directory.path)
        }
        var skills: [Skill] = []
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            skills.append(try Self.load(folder))
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
            name: name, description: description, body: parsed.body, files: files(in: folder), directory: folder)
    }

    private static func files(in folder: URL) -> [String] {
        let base = folder.standardizedFileURL.path + "/"
        let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
        var files: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(base.count))
            if path != "SKILL.md" { files.append(path) }
        }
        return files.sorted()
    }
}
```

If `standardizedFileURL` and the enumerator disagree about `/private` on temporary directories (the relative paths come out wrong), use `resolvingSymlinksInPath()` on both `folder` and each `url` instead.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/SwiftUIAssistant && xcrun swift test --filter SkillLibraryTests`
Expected: all 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Skills Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/SkillLibraryTests.swift
git commit -m "feat(assistant): load skills from folders"
```

---

### Task 2: `list_skills` and `get_skill` tools

**Files:**

- Create: `Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Skills/SkillTools.swift`
- Test: `Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/SkillToolsTests.swift`

**Interfaces:**

- Consumes: `SkillLibrary`, `Skill` from Task 1.
- Produces:
  - `public struct ListSkillsTool: AssistantTool { public init(library: SkillLibrary) }`, name `list_skills`
  - `public struct GetSkillTool: AssistantTool { public init(library: SkillLibrary) }`, name `get_skill`, parameters `name` (required string) and `file` (optional string)

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import SwiftUIAssistant

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
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
        let tool = GetSkillTool(library: try library())
        let joints = try await tool.execute(arguments: ["name": "joints"])
        #expect(joints.success)
        #expect(joints.message == "# Joints\nUse add_joint.\n\nFiles: binary.bin, recipes.md, reference/limits.md")
        let sketches = try await tool.execute(arguments: ["name": "sketches"])
        #expect(sketches.message == "Sketch.\n")
    }

    @Test("get_skill with a file returns that file, also from a subfolder")
    func file() async throws {
        let tool = GetSkillTool(library: try library())
        #expect(try await tool.execute(arguments: ["name": "joints", "file": "recipes.md"]).message == "Lid on a box.\n")
        #expect(try await tool.execute(arguments: ["name": "joints", "file": "reference/limits.md"]).message == "Limits.\n")
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

    @Test("Files outside the skill's list are refused", arguments: ["nope.md", "../sketches/SKILL.md", "/etc/passwd", "SKILL.md"])
    func unlistedFile(file: String) async throws {
        let result = try await GetSkillTool(library: library()).execute(arguments: ["name": "joints", "file": .string(file)])
        #expect(!result.success)
        #expect(result.message == "Skill 'joints' has no file '\(file)'. Files: binary.bin, recipes.md, reference/limits.md")
    }

    @Test("A skill without other files says so when a file is asked for")
    func noFiles() async throws {
        let result = try await GetSkillTool(library: library()).execute(arguments: ["name": "sketches", "file": "x.md"])
        #expect(result.message == "Skill 'sketches' has no file 'x.md'. It has no other files.")
    }

    @Test("A file that is not UTF-8 text is refused")
    func binary() async throws {
        let result = try await GetSkillTool(library: library()).execute(arguments: ["name": "joints", "file": "binary.bin"])
        #expect(!result.success)
        #expect(result.message == "binary.bin in skill 'joints' is not a text file.")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/SwiftUIAssistant && xcrun swift test --filter SkillToolsTests`
Expected: build failure, `cannot find 'ListSkillsTool' in scope`.

- [ ] **Step 3: Implement**

`Skills/SkillTools.swift`:

```swift
import Foundation

public struct ListSkillsTool: AssistantTool {
    let library: SkillLibrary

    public init(library: SkillLibrary) {
        self.library = library
    }

    public let name = "list_skills"

    public let description = "Lists the skills: guides for kinds of work, each with what it covers. Read one with get_skill."

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
        guard case .string(let name) = arguments["name"] else { return .failure("'name' must be a skill name.") }
        guard let skill = library.skill(named: name) else {
            let names = library.skills.map(\.name).joined(separator: ", ")
            return .failure("No skill named '\(name)'. Skills: \(names).")
        }
        guard case .string(let file) = arguments["file"] else {
            return .success(skill.files.isEmpty ? skill.body : "\(skill.body)\nFiles: \(skill.files.joined(separator: ", "))")
        }
        guard skill.files.contains(file) else {
            let listing = skill.files.isEmpty ? "It has no other files." : "Files: \(skill.files.joined(separator: ", "))"
            return .failure("Skill '\(name)' has no file '\(file)'. \(listing)")
        }
        guard let text = try? String(contentsOf: skill.directory.appending(path: file), encoding: .utf8) else {
            return .failure("\(file) in skill '\(name)' is not a text file.")
        }
        return .success(text)
    }
}
```

The body ends with a newline (see Task 1), so `"\(skill.body)\nFiles: …"` leaves one blank line between them, matching the test. If `.string(...)` pattern on `JSONValue` differs, check `Core/JSONValue.swift` for the case name.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/SwiftUIAssistant && xcrun swift test`
Expected: the whole SwiftUIAssistant suite passes.

- [ ] **Step 5: Commit**

```bash
git add Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Skills/SkillTools.swift Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/SkillToolsTests.swift
git commit -m "feat(assistant): add list_skills and get_skill tools"
```

---

### Task 3: Bundle the CAD skills and register the tools

This task creates the three skill folders from the current prompt text (the prompt itself changes in Task 4) and registers the tools.

**Files:**

- Create: `Packages/CADAssistantTools/Sources/CADAssistantTools/Resources/Skills/sketches/SKILL.md`
- Create: `Packages/CADAssistantTools/Sources/CADAssistantTools/Resources/Skills/assemblies/SKILL.md`
- Create: `Packages/CADAssistantTools/Sources/CADAssistantTools/Resources/Skills/joints/SKILL.md`
- Create: `Packages/CADAssistantTools/Sources/CADAssistantTools/CADSkills.swift`
- Modify: `Packages/CADAssistantTools/Package.swift` (the `CADAssistantTools` target)
- Modify: `Packages/CADAssistantTools/Sources/CADAssistantTools/CADTools.swift`
- Test: `Packages/CADAssistantTools/Tests/CADAssistantToolsTests/CADSkillsTests.swift`

**Interfaces:**

- Consumes: `SkillLibrary`, `ListSkillsTool`, `GetSkillTool` from Tasks 1–2.
- Produces: `public enum CADSkills { public static let library: SkillLibrary }`; `CADTools.all(session:)` includes `list_skills` and `get_skill`.

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("CAD skills")
struct CADSkillsTests {
    @Test("The bundled skills load")
    func bundled() {
        #expect(CADSkills.library.skills.map(\.name) == ["assemblies", "joints", "sketches"])
    }

    @Test("The sketches skill teaches fully constraining, tangentAt joints and sketch face names")
    func sketches() throws {
        let body = try #require(CADSkills.library.skill(named: "sketches")).body
        #expect(body.hasPrefix("## Sketches\n"))
        #expect(body.contains("add_sketch"))
        #expect(body.contains("tangentAt"))
        #expect(body.contains("fully constrained"))
        #expect(body.contains("Extrude1.side[Sketch1.line3]"))
    }

    @Test("The assemblies skill teaches instances")
    func assemblies() throws {
        let body = try #require(CADSkills.library.skill(named: "assemblies")).body
        #expect(body.hasPrefix("## Parts and assemblies\n"))
        #expect(body.contains("add_instance"))
    }

    @Test("The joints skill teaches mating, that aligned axes need flip, and motion")
    func joints() throws {
        let body = try #require(CADSkills.library.skill(named: "joints")).body
        #expect(body.hasPrefix("## Joints (mating)\n"))
        #expect(body.contains("flip: true when the two axes point the same way"))
        #expect(!body.contains("use flip if the axes point opposite ways"))
        #expect(body.contains("## Motion\n"))
        #expect(body.contains("move_joint(joint, value)"))
    }

    @Test("The CAD tools include the skill tools")
    func registered() {
        let session = CADSession(document: CADDocument(parts: [Part(name: "P")]), kernel: FakeKernel())
        let names = CADTools.all(session: session).map(\.name)
        #expect(names.contains("list_skills"))
        #expect(names.contains("get_skill"))
    }
}
```

Add `import CADModel` at the top as well (for `CADDocument` and `Part`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/CADAssistantTools && xcrun swift test --filter CADSkillsTests`
Expected: build failure, `cannot find 'CADSkills' in scope`.

- [ ] **Step 3: Extract the skill files from the current prompt**

Run this from the repository root. It evaluates the Swift multiline string the way the compiler does for this file (8-space indent removed, a trailing `\` joins the next line; the file has no other escapes) and writes each skill's `SKILL.md`, the section text unchanged:

```bash
python3 - <<'EOF'
import pathlib, re
src = pathlib.Path("Packages/CADAssistantTools/Sources/CADAssistantTools/CADAssistantPrompt.swift").read_text()
raw = src.split('system = """\n', 1)[1].split('\n        """', 1)[0]
text = "\n".join(line[8:] for line in raw.split("\n")).replace("\\\n", "")
sections = {m.group(1): m.group(0).rstrip("\n") + "\n" for m in re.finditer(r"^## (.+)\n(?:(?!## ).*\n?)*", text, re.M)}
skills = {
    "sketches": ("Constrained sketches and the extrude and revolve features made from them. Load before add_sketch, edit_sketch, or adding an extrude or revolve.",
                 [sections["Sketches"]]),
    "assemblies": ("Parts, and the assembly that places them as instances. Load before add_part, add_instance or edit_instance.",
                   [sections["Parts and assemblies"]]),
    "joints": ("Joints that mate instances, and moving mechanisms through them. Load before add_joint, edit_joint or move_joint.",
               [sections["Joints (mating)"], sections["Motion"]]),
}
root = pathlib.Path("Packages/CADAssistantTools/Sources/CADAssistantTools/Resources/Skills")
for name, (description, parts) in skills.items():
    folder = root / name
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "SKILL.md").write_text(f"---\nname: {name}\ndescription: {description}\n---\n" + "\n".join(parts))
EOF
```

Check: `head -5 Packages/CADAssistantTools/Sources/CADAssistantTools/Resources/Skills/joints/SKILL.md` shows the frontmatter then `## Joints (mating)`, and `grep -c '\\' …/SKILL.md` prints 0 for each file.

- [ ] **Step 4: Bundle the folder, load it, register the tools**

In `Packages/CADAssistantTools/Package.swift`, give the `CADAssistantTools` target its resources:

```swift
        .target(
            name: "CADAssistantTools",
            dependencies: [
                .product(name: "SwiftUIAssistant", package: "SwiftUIAssistant"),
                .product(name: "CADModel", package: "CADModel"),
            ],
            resources: [.copy("Resources/Skills")]
        ),
```

`Sources/CADAssistantTools/CADSkills.swift`:

```swift
import Foundation
import SwiftUIAssistant

public enum CADSkills {
    /// The skills bundled with the tools. They ship with the app, so a broken one is a bug the tests catch.
    public static let library: SkillLibrary = {
        guard let directory = Bundle.module.url(forResource: "Skills", withExtension: nil) else {
            fatalError("The bundled skills folder is missing.")
        }
        do {
            return try SkillLibrary(directory: directory)
        } catch {
            fatalError("A bundled skill is broken: \(error)")
        }
    }()
}
```

In `CADTools.all(session:)`, append after `MoveJointTool(session: session),`:

```swift
            ListSkillsTool(library: CADSkills.library),
            GetSkillTool(library: CADSkills.library),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd Packages/CADAssistantTools && xcrun swift test --filter CADSkillsTests`
Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/CADAssistantTools/Package.swift Packages/CADAssistantTools/Sources/CADAssistantTools/Resources Packages/CADAssistantTools/Sources/CADAssistantTools/CADSkills.swift Packages/CADAssistantTools/Sources/CADAssistantTools/CADTools.swift Packages/CADAssistantTools/Tests/CADAssistantToolsTests/CADSkillsTests.swift
git commit -m "feat(tools): bundle sketch, assembly and joint skills"
```

---

### Task 4: Move the sections out of the system prompt

**Files:**

- Modify: `Packages/CADAssistantTools/Sources/CADAssistantTools/CADAssistantPrompt.swift`
- Modify: `Packages/CADAssistantTools/Tests/CADAssistantToolsTests/AssistantLoopTests.swift` (replace `promptSketches` and `promptJoints`, add a loop test)

**Interfaces:**

- Consumes: `CADSkills.library.index` from Task 3; `SketchToolTests.rectangle` and `rectangleConstraints` (test target); `FakeKernel`, `FakeSketchSolver`.
- Produces: `CADAssistantPrompt.system` = core sections + Skills section; `CADAssistantPrompt.configuration` unchanged in shape.

- [ ] **Step 1: Write the failing tests**

In `AssistantLoopTests.swift`, delete `promptSketches` and `promptJoints` (their checks now live in `CADSkillsTests`) and add:

```swift
    @Test("The prompt keeps the core sections, lists the skills and no longer carries the moved sections")
    func promptSkills() {
        let prompt = CADAssistantPrompt.system
        for heading in ["## The model", "## Faces and edges", "## Skills", "## Working"] {
            #expect(prompt.contains(heading))
        }
        for heading in ["## Sketches", "## Parts and assemblies", "## Joints (mating)", "## Motion"] {
            #expect(!prompt.contains(heading))
        }
        #expect(prompt.contains(CADSkills.library.index))
        #expect(prompt.contains("get_skill"))
    }

    @Test("A scripted model loads the sketches skill, then sketches")
    func loadsSkillThenSketches() async throws {
        let session = CADSession(
            document: Fixtures.plateParametersOnly(), kernel: FakeKernel(), sketchSolver: FakeSketchSolver())
        let provider = ScriptedProvider([
            LLMResponse(content: nil, toolCalls: [call("1", "get_skill", ["name": "sketches"])], stopReason: .toolUse),
            LLMResponse(
                content: nil,
                toolCalls: [
                    call(
                        "2", "add_sketch",
                        [
                            "plane": "XY", "entities": SketchToolTests.rectangle,
                            "constraints": SketchToolTests.rectangleConstraints,
                        ])
                ], stopReason: .toolUse),
            LLMResponse(content: "Sketched the outline.", toolCalls: nil, stopReason: .endTurn),
        ])
        let assistant = Assistant(
            provider: provider, tools: CADTools.all(session: session),
            contextProvider: { session.assistantContext() }, configuration: CADAssistantPrompt.configuration)

        try await assistant.send("Sketch a 60 by 40 outline.")

        let results = await provider.requests[2].history.filter { $0.role == .toolResult }.map(\.content)
        #expect(results.count == 2)
        #expect(results[0].hasPrefix("Success: ## Sketches\n"))
        #expect(results[1].hasPrefix("Success: "))
        #expect(session.document.parts[0].features.map(\.name) == ["Sketch1"])
    }
```

`Fixtures.plateParametersOnly()` defines the `width` parameter that `rectangleConstraints` uses, and one part with no features.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/CADAssistantTools && xcrun swift test --filter AssistantLoopTests`
Expected: `promptSkills` fails (`## Skills` missing, `## Sketches` present); `loadsSkillThenSketches` passes already (the tool is registered), which is fine.

- [ ] **Step 3: Split the prompt**

In `CADAssistantPrompt.swift`:

1. Rename the existing string to `private static let core` and delete from the line `## Sketches` up to (not including) the line `## Working`, i.e. the Sketches, Parts and assemblies, Joints (mating) and Motion sections, leaving one blank line before `## Working`.
2. Add, above `core`:

```swift
    /// The system prompt for a modelling assistant using `CADTools`. It has no `{context}` placeholder: the listing
    /// changes every turn, so it travels with each user message instead (`attachesContextToMessages`).
    public static let system = core.replacingOccurrences(of: "## Working", with: skills + "\n\n## Working")

    private static let skills = """
        ## Skills
        Detailed guides for some kinds of work are skills. Before your first write of a kind a skill covers, call \
        get_skill with its name and follow it; you need not load it again in the same conversation. A skill may \
        list more files; read one with get_skill(name, file) when the guide points you to it.
        \(CADSkills.library.index)
        """
```

(move the existing doc comment from the old `system` to the new one; `configuration` stays as it is and keeps using `system`).

- [ ] **Step 4: Run the whole package's tests**

Run: `cd Packages/CADAssistantTools && xcrun swift test`
Expected: all tests pass, including `CADBenchTests`.

- [ ] **Step 5: Commit**

```bash
git add Packages/CADAssistantTools/Sources/CADAssistantTools/CADAssistantPrompt.swift Packages/CADAssistantTools/Tests/CADAssistantToolsTests/AssistantLoopTests.swift
git commit -m "feat(tools): load sketch, assembly and joint guidance as skills"
```

---

### Task 5: App build, docs and bench

**Files:**

- Modify: `CLAUDE.md` (SwiftUIAssistant and CADAssistantTools sections)

- [ ] **Step 1: Build the app and check the skills are in the bundle**

```bash
xcodegen generate
xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp -derivedDataPath build/DerivedData build
find build/DerivedData/Build/Products -path '*Skills/joints/SKILL.md'
```

Expected: build succeeds; `find` prints one path inside the app's embedded `CADAssistantTools_CADAssistantTools.bundle`. If it prints nothing, the resource bundle is not embedded and the app would hit the `fatalError` on first use; fix before going on.

- [ ] **Step 2: Run the app tests**

Run: `xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test`
Expected: pass.

- [ ] **Step 3: Update `CLAUDE.md`**

Under **SwiftUIAssistant**, add a bullet:

```markdown
- Skills - `SkillLibrary(directory:)` loads each subfolder with a `SKILL.md` (frontmatter `name` = folder name, `description`) as a `Skill` with its other files; `ListSkillsTool` (`list_skills`) and `GetSkillTool` (`get_skill(name, file?)`, only the skill's listed text files). Nothing in a skill is executed
```

Under **CADAssistantTools**, add to the tools line `list_skills`, `get_skill`, and add a bullet:

```markdown
- Skills - `Sources/CADAssistantTools/Resources/Skills/<name>/SKILL.md`, bundled with `.copy` and loaded once by `CADSkills.library`: `sketches`, `assemblies`, `joints` (with motion). `CADAssistantPrompt.system` keeps the core (the model, faces and edges, working) and lists the skills; the model loads one before its first write of that kind
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: describe assistant skills"
```

- [ ] **Step 5: Bench before and after**

This calls the Claude API and costs money; confirm with the user before running. It needs `ANTHROPIC_API_KEY`.

```bash
git worktree add .claude/worktrees/bench-base main
xcrun swift run --package-path .claude/worktrees/bench-base/Packages/CADAssistantTools cadbench run --repeat 3
xcrun swift run --package-path Packages/CADAssistantTools cadbench run --repeat 3
git worktree remove .claude/worktrees/bench-base
```

Put a table of pass@1, pass@3, tool calls, input tokens and cost per task, before and after, in the PR description. If sketch or joint tasks drop because the model skipped `get_skill`, report it; the fix (a hint in the first covered write's result) is a follow-up, not part of this PR.
