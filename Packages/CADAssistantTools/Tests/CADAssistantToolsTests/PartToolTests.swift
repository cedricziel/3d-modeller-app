@testable import CADAssistantTools
import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@MainActor
@Suite("add_part, rename_part, delete_part")
struct PartToolTests {
    @Test("Parts are added, renamed and deleted, each as one undo step")
    func addRenameDeletePart() async throws {
        let harness = Harness()

        let added = try await harness.call("add_part", ["name": "Leg"])
        let renamed = try await harness.call("rename_part", ["part": "Leg", "new_name": "Post"])
        let listing = harness.session.listing
        let deleted = try await harness.call("delete_part", ["part": "Post"])

        #expect(added.message.hasPrefix("Added part Leg"))
        #expect(renamed.message.hasPrefix("Renamed part Leg to Post"))
        #expect(listing.contains("part Post\n  (no features)"))
        #expect(deleted.message.hasPrefix("Deleted part Post"))
        #expect(harness.document.parts.map(\.name) == ["Plate"])
        #expect(harness.commits == ["Add part Leg", "Rename part Leg to Post", "Delete part Post"])
    }

    @Test("A new part without a name gets the next free Part<n>")
    func defaultName() async throws {
        let harness = Harness(CADDocument(parts: [Part(name: "Part1")]))

        _ = try await harness.call("add_part", [:])

        #expect(harness.document.parts.map(\.name) == ["Part1", "Part2"])
    }

    @Test("Names must be identifiers, unique among parts")
    func nameRefusals() async throws {
        let harness = Harness()

        #expect(
            try await harness.refused("add_part", ["name": "Plate"])
                == "A part named Plate already exists."
        )
        #expect(
            try await harness.refused("add_part", ["name": "a b"])
                == "'a b' is not a valid part name: use letters, digits and _, starting with a letter or _."
        )
        #expect(
            try await harness.refused("rename_part", ["part": "Nope", "new_name": "X"])
                == "No part named 'Nope'. Parts: Plate."
        )
    }

    @Test("The last part, and parts that instances place, cannot be deleted")
    func deletePartRefused() async throws {
        let plate = Part(name: "Plate")
        let document = CADDocument(
            parts: [plate, Part(name: "Spare")],
            assembly: Assembly(instances: [
                Instance(name: "Leg1", part: plate.id), Instance(name: "Leg2", part: plate.id),
            ])
        )
        let harness = Harness(document)

        #expect(
            try await harness.refused("delete_part", ["part": "Plate"])
                == "Part Plate is placed by instances Leg1, Leg2; delete them first."
        )
        #expect(
            try await Harness().refused("delete_part", ["part": "Plate"])
                == "Plate is the only part; a document keeps at least one."
        )
    }
}
