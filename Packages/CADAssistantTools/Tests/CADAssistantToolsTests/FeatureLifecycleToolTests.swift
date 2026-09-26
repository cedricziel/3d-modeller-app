import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("delete_feature, rename_feature, suppress_feature, get_listing")
struct FeatureLifecycleToolTests {
    /// A, B and C each create a body; D cuts Body2 (B's), E moves Body3 (C's), F subtracts Body3 from Body2.
    private func threeBodies() -> CADDocument {
        CADDocument(parts: [
            Part(
                name: "P",
                features: [
                    Fixtures.box("A", 1, 1, 1),
                    Fixtures.box("B", 10, 10, 10),
                    Fixtures.box("C", 2, 2, 2),
                    Fixtures.box("D", 1, 1, 1, .cut("Body2")),
                    Feature(
                        name: "E",
                        kind: .transform(
                            TransformFeature(body: "Body3", placement: Placement(translation: Vector3(1, 0, 0))))),
                    Feature(
                        name: "F",
                        kind: .boolean(BooleanFeature(operation: .subtract, target: "Body2", tools: ["Body3"]))),
                ])
        ])
    }

    @Test("Deleting a feature that creates nothing others use removes it and reports what changed")
    func deleteLeaf() async throws {
        let harness = Harness(Fixtures.plate())

        let result = try await harness.call("delete_feature", ["feature": "Hole"])

        #expect(result.success)
        #expect(harness.commits == ["Delete Hole"])
        #expect(harness.features() == ["Base", "Pin", "BadCone", "Merge", "Move"])
        #expect(result.message.hasPrefix("Deleted Hole from part Plate\n"))
        #expect(
            result.message.contains("- Hole  cylinder r=hole_r h=t at (width / 2, depth / 2, 0), cut Body1 → Body1  ok")
        )
    }

    @Test("Ruling: deleting an earlier body renumbers later references so they keep their bodies")
    func deleteRenumbers() async throws {
        let harness = Harness(threeBodies())
        let before = try #require(await harness.session.currentResult())

        let result = try await harness.call("delete_feature", ["feature": "A"])

        #expect(result.success)
        let kinds = harness.document.parts[0].features.map(\.kind.bodyReferences)
        #expect(kinds == [[], [], ["Body1"], ["Body2"], ["Body1", "Body2"]])
        #expect(
            result.message.contains(
                """
                Body references renumbered:
                  D now refers to Body1 (was Body2)
                  E now refers to Body2 (was Body3)
                  F now refers to Body1 (was Body2), Body2 (was Body3)
                """))
        let after = try #require(harness.session.result)
        #expect(after.parts[0].features.map(\.status) == [.ok, .ok, .ok, .ok, .ok])
        #expect(
            after.parts[0].bodies.map(\.metrics?.volume)
                == before.parts[0].bodies.dropFirst().prefix(1).map(\.metrics?.volume))
    }

    @Test("Ruling: deleting a feature whose body others use is refused and names them")
    func deleteUsedBodyRefused() async throws {
        let harness = Harness(threeBodies())

        let message = try await harness.refused("delete_feature", ["feature": "C"])

        #expect(
            message == """
                Nothing changed, because bodies that other features use would no longer exist: \
                E uses Body3, which C creates; F uses Body3, which C creates. Change or delete those features first, \
                or suppress the creating feature instead.
                """)
    }

    @Test("Deleting an unknown feature, or an ambiguous one, is refused")
    func deleteRefusals() async throws {
        let sphere = { Feature(name: "S", kind: .primitive(PrimitiveFeature(.sphere(radius: 1)))) }
        let harness = Harness(
            CADDocument(parts: [Part(name: "A", features: [sphere()]), Part(name: "B", features: [sphere()])]))

        #expect(
            try await harness.refused("delete_feature", ["feature": "T"])
                == "No feature named 'T'. Features by part: A: S; B: S.")
        #expect(
            try await harness.refused("delete_feature", ["feature": "S"])
                == "Several parts have a feature named 'S' (A, B); say which one with 'part'.")
        #expect(try await harness.call("delete_feature", ["feature": "S", "part": "B"]).success)
        #expect(harness.document.parts.map(\.features.count) == [1, 0])
    }

    @Test("Renaming keeps references, since they point at ids and bodies, not names")
    func rename() async throws {
        let harness = Harness(Fixtures.plate())

        let result = try await harness.call("rename_feature", ["feature": "BadCone", "new_name": "Cone"])

        #expect(result.success)
        #expect(harness.commits == ["Rename BadCone to Cone"])
        #expect(result.message.contains("Cone: failed: cone radii must differ"))
        #expect(result.message.contains("Merge: skipped: depends on BadCone → skipped: depends on Cone"))
        #expect(
            try await harness.refused("rename_feature", ["feature": "Cone", "new_name": "Base"])
                == "Part Plate already has a feature named 'Base'.")
        #expect(
            try await harness.refused("rename_feature", ["feature": "Cone", "new_name": "1st"])?.hasPrefix(
                "'1st' is not a valid feature name") == true)
        #expect(
            try await harness.refused("rename_feature", ["feature": "Nope", "new_name": "X"])?.hasPrefix(
                "No feature named 'Nope'") == true)
        #expect(
            try await harness.call("rename_feature", ["feature": "Cone", "new_name": "Cone"]).message
                == "Renamed Cone to Cone. Nothing changed.")
    }

    @Test("Suppressing skips dependants; unsuppressing restores them; each is one named undo step")
    func suppress() async throws {
        let harness = Harness(Fixtures.plate())

        let suppressed = try await harness.call("suppress_feature", ["feature": "Base"])
        #expect(suppressed.success)
        #expect(suppressed.message.contains("Base: suppressed"))
        #expect(suppressed.message.contains("Hole: ok → skipped: depends on Base"))

        let restored = try await harness.call("suppress_feature", ["feature": "Base", "suppressed": false])
        #expect(restored.message.contains("Base: ok"))
        #expect(harness.commits == ["Suppress Base", "Unsuppress Base"])
        #expect(
            try await harness.call("suppress_feature", ["feature": "Pin"]).message == "Suppressed Pin. Nothing changed."
        )
        #expect(
            try await harness.refused("suppress_feature", ["feature": "Pin", "suppressed": "yes"])
                == "'suppressed' must be true or false.")
    }

    @Test("get_listing rebuilds when needed and returns the listing with statuses")
    func getListing() async throws {
        let plate = Fixtures.plate()
        let harness = Harness(plate)

        let result = try await harness.call("get_listing", [:])

        #expect(result.success)
        #expect(result.message == DocumentListing.render(plate, result: harness.session.result))
        #expect(result.message.contains("Base  box width×depth×t at origin → Body1  ok"))
        #expect(harness.commits.isEmpty)
    }

    @Test("Every tool is offered with a unique name, and descriptions state the units")
    func toolSet() {
        let tools = CADTools.all(session: Harness().session)
        #expect(
            tools.map(\.name) == [
                "get_listing", "find_geometry", "measure", "set_parameter", "add_feature", "edit_feature",
                "delete_feature", "rename_feature", "suppress_feature",
            ])
        for name in ["get_listing", "measure", "set_parameter", "add_feature", "edit_feature"] {
            let description = tools.first { $0.name == name }?.description ?? ""
            #expect(description.contains("mm") && description.contains("degrees"), "\(name)")
        }
    }
}
