@testable import CADAssistantTools
import CADModel
import SwiftUIAssistant
import Testing

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
