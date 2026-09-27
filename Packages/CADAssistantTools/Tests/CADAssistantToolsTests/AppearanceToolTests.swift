@testable import CADAssistantTools
import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@MainActor
@Suite("set_appearance")
struct AppearanceToolTests {
    private func ornaments() async throws -> Harness {
        let harness = Harness(CADDocument(parts: [Part(name: "Ornament")]))
        _ = try await harness.call("add_feature", ["name": "Ball", "type": "sphere", "radius": 5])
        _ = try await harness.call("add_instance", ["part": "Ornament", "name": "O1"])
        _ = try await harness.call("add_instance", ["part": "Ornament", "name": "O2"])
        return harness
    }

    @Test("A part's appearance is set in one undo step and shows on the part's listing line")
    func setPart() async throws {
        let harness = try await ornaments()

        let result = try await harness.call(
            "set_appearance", ["part": "Ornament", "color": "#2e7d32", "metallic": 0.8, "roughness": 0.25]
        )

        let appearance = try #require(harness.document.parts[0].appearance)
        #expect(result.success)
        #expect(result.message.hasPrefix("Set the appearance of part Ornament to #2E7D32 metallic 0.8 roughness 0.25"))
        #expect(result.message.contains("+ part Ornament  #2E7D32 metallic 0.8 roughness 0.25"))
        #expect(appearance.color == HexColor(red: 0x2E, green: 0x7D, blue: 0x32))
        #expect(appearance.metallic == 0.8)
        #expect(appearance.roughness == 0.25)
        #expect(harness.commits.last == "Set appearance of Ornament")
        #expect(harness.session.listing.contains("part Ornament  #2E7D32 metallic 0.8 roughness 0.25"))
    }

    @Test("An instance's appearance overrides its part's, and clearing it restores the part's")
    func setInstance() async throws {
        let harness = try await ornaments()
        _ = try await harness.call("set_appearance", ["part": "Ornament", "color": "#2E7D32"])

        let set = try await harness.call("set_appearance", ["instance": "O2", "color": "C62828"])
        let overridden = harness.session.result?.assembly?.instance(named: "O2")?.appearance

        #expect(set.message.hasPrefix("Set the appearance of instance O2 to #C62828"))
        #expect(set.message.contains("Unchanged instances: O1, O2"))
        #expect(set.message.contains("+ O2  Ornament at origin, #C62828"))
        #expect(harness.document.instances[1].appearance?.color.hex == "#C62828")
        #expect(harness.document.instances[0].appearance == nil)
        #expect(overridden?.color.hex == "#C62828")
        #expect(harness.session.result?.assembly?.instance(named: "O1")?.appearance?.color.hex == "#2E7D32")
        #expect(harness.session.listing.contains("O2  Ornament at origin, #C62828  ok"))

        let cleared = try await harness.call("set_appearance", ["instance": "O2", "clear": true])

        #expect(cleared.message.hasPrefix("Cleared the appearance of instance O2; it shows its part's"))
        #expect(harness.document.instances[1].appearance == nil)
        #expect(harness.session.result?.assembly?.instance(named: "O2")?.appearance?.color.hex == "#2E7D32")
        #expect(harness.commits.suffix(2) == ["Set appearance of O2", "Clear appearance of O2"])
    }

    @Test("Bad colours, factors, targets and combinations are refused without changing anything")
    func refusals() async throws {
        let harness = try await ornaments()

        #expect(
            try await harness.refused("set_appearance", ["part": "Ornament", "color": "green"])
                == "'green' is not a colour; give six hex digits such as #2E7D32."
        )
        #expect(
            try await harness.refused("set_appearance", ["part": "Ornament", "color": "#12345"])
                == "'#12345' is not a colour; give six hex digits such as #2E7D32."
        )
        #expect(
            try await harness.refused("set_appearance", ["part": "Ornament", "color": "#123456", "roughness": 1.5])
                == "roughness must be between 0 and 1, not 1.5"
        )
        #expect(
            try await harness.refused("set_appearance", ["part": "Ornament", "color": "#123456", "metallic": "shiny"])
                == "'metallic' must be a number between 0 and 1."
        )
        #expect(
            try await harness.refused("set_appearance", ["part": "Nope", "color": "#123456"])
                == "No part named 'Nope'. Parts: Ornament."
        )
        #expect(
            try await harness.refused("set_appearance", ["instance": "O9", "color": "#123456"])
                == "No instance named 'O9'. Instances: O1, O2."
        )
        #expect(
            try await harness.refused("set_appearance", ["color": "#123456"])
                == "Give either 'part' or 'instance'."
        )
        #expect(
            try await harness.refused("set_appearance", ["part": "Ornament", "instance": "O1", "color": "#123456"])
                == "Give either 'part' or 'instance'."
        )
        #expect(
            try await harness.refused("set_appearance", ["part": "Ornament"])
                == "Give 'color', or clear: true to remove the appearance."
        )
        #expect(
            try await harness.refused("set_appearance", ["part": "Ornament", "clear": true, "color": "#123456"])
                == "clear: true removes the appearance; leave out color, metallic and roughness."
        )
    }

    @Test("Clearing an appearance that is not set changes nothing")
    func clearUnset() async throws {
        let harness = try await ornaments()
        let commits = harness.commits.count

        let result = try await harness.call("set_appearance", ["part": "Ornament", "clear": true])

        #expect(result.success)
        #expect(result.message == "Cleared the appearance of part Ornament. Nothing changed.")
        #expect(harness.commits.count == commits)
    }
}
