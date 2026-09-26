@testable import CADAssistantTools
import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@MainActor
@Suite("add_instance, edit_instance, delete_instance")
struct InstanceToolTests {
    private func plate() async throws -> Harness {
        let harness = Harness()
        _ = try await harness.call(
            "add_feature", ["name": "Box", "type": "box", "width": 60, "depth": 40, "height": 5]
        )
        return harness
    }

    @Test("Instances get default names and report their status and bounds")
    func addInstanceDefaults() async throws {
        let harness = try await plate()

        let first = try await harness.call("add_instance", ["part": "Plate", "grounded": true])
        let second = try await harness.call(
            "add_instance", ["part": "Plate", "placement": ["translation": ["z": 5]]]
        )

        #expect(harness.document.instances.map(\.name) == ["Plate1", "Plate2"])
        #expect(harness.document.instances[0].grounded)
        #expect(first.message.hasPrefix("Added instance Plate1 of part Plate\nPlate1: ok"))
        #expect(second.message.contains("Plate2 (Plate): ok, bounds (0, 0, 5) to (60, 40, 10)"))
        #expect(second.message.contains("Unchanged instances: Plate1"))
        #expect(second.message.contains("+ Plate2  Plate at (0, 0, 5)  ok"))
        #expect(harness.commits.suffix(2) == ["Add instance Plate1", "Add instance Plate2"])
    }

    @Test("Instances are refused for unknown parts and bodies, bad or taken names and bad expressions")
    func addInstanceRefusals() async throws {
        let harness = try await plate()
        _ = try await harness.call("add_instance", ["part": "Plate", "name": "Base"])

        #expect(
            try await harness.refused("add_instance", ["part": "Nope"])
                == "No part named 'Nope'. Parts: Plate."
        )
        #expect(
            try await harness.refused("add_instance", ["part": "Plate", "name": "A B"])
                == "'A B' is not a valid instance name: use letters, digits and _, starting with a letter or _."
        )
        #expect(
            try await harness.refused("add_instance", ["part": "Plate", "name": "Base"])
                == "An instance named Base already exists."
        )
        #expect(
            try await harness.refused("add_instance", ["part": "Plate", "body": "Body9"])
                == "Part Plate has no body named Body9. Bodies: Body1."
        )
        let expression = try await harness.refused(
            "add_instance", ["part": "Plate", "placement": ["translation": ["z": "missing + 1"]]]
        )
        #expect(expression?.contains("Plate1.placement.translation.z = missing + 1") == true)
    }

    @Test("Editing merges placement fields and changes grounding and the name")
    func editInstanceMerges() async throws {
        let harness = try await plate()
        _ = try await harness.call(
            "add_instance", ["part": "Plate", "name": "Lid", "placement": ["translation": [10, 20, 5]]]
        )

        let moved = try await harness.call(
            "edit_instance", ["instance": "Lid", "placement": ["translation": ["z": 30]], "grounded": true]
        )
        _ = try await harness.call("edit_instance", ["instance": "Lid", "new_name": "Cover"])
        let instance = try #require(harness.document.instance(named: "Cover"))

        #expect(moved.message.contains("Lid (Plate): ok, bounds (10, 20, 30) to (70, 60, 35)"))
        #expect(instance.placement.translation == Vector3(10, 20, 30))
        #expect(instance.grounded)
        #expect(
            try await harness.refused("edit_instance", ["instance": "Cover"])
                == "Give at least one of placement, grounded, new_name."
        )
        #expect(
            try await harness.refused("edit_instance", ["instance": "Lid", "grounded": false])
                == "No instance named 'Lid'. Instances: Cover."
        )
    }

    @Test("Deleting an instance leaves the part")
    func deleteInstance() async throws {
        let harness = try await plate()
        _ = try await harness.call("add_instance", ["part": "Plate", "name": "Lid"])

        let result = try await harness.call("delete_instance", ["instance": "Lid"])

        #expect(result.message.hasPrefix("Deleted instance Lid"))
        #expect(result.message.contains("Removed instances: Lid"))
        #expect(harness.document.instances.isEmpty)
        #expect(harness.document.parts[0].features.count == 1)
    }

    @Test("An instance's body follows renumbering, and an edit that removes it is refused")
    func instanceBodyRepaired() async throws {
        let plate = Part(name: "Plate", features: [Fixtures.box("A", 1, 1, 1), Fixtures.box("B", 2, 2, 2)])
        let harness = Harness(
            CADDocument(
                parts: [plate], assembly: Assembly(instances: [Instance(name: "Lid", part: plate.id, body: "Body2")]))
        )
        try await harness.session.rebuild()

        #expect(
            try await harness.refused("delete_feature", ["feature": "B"])?.contains("Lid uses Body2, which B creates")
                == true
        )
        let result = try await harness.call("delete_feature", ["feature": "A"])

        #expect(harness.document.instances[0].body == "Body1")
        #expect(result.message.contains("Lid now refers to Body1 (was Body2)"))
    }
}
