import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("Fillet, chamfer and shell through the feature tools")
struct DressUpToolTests {
    private func harnessWithBase() async throws -> Harness {
        let harness = Harness()
        _ = try await harness.call(
            "add_feature", ["name": "Base", "type": "box", "width": 60, "depth": 40, "height": 10])
        return harness
    }

    @Test("A fillet takes edge names and filters, and the listing shows them")
    func addFillet() async throws {
        let harness = try await harnessWithBase()

        let result = try await harness.call(
            "add_feature",
            ["type": "fillet", "body": "Body1", "edges": ["edge(Base.top, Base.front)", "parallel Z"], "radius": 2])

        #expect(result.success)
        #expect(
            harness.document.parts[0].features[1].kind
                == .fillet(
                    FilletFeature(
                        body: "Body1", edges: [.name("edge(Base.top, Base.front)"), .filter("parallel Z")], radius: 2)))
        #expect(result.message.contains("Fillet1: ok"))
        #expect(
            result.message.contains(
                #"+ Fillet1  fillet Body1 edges edge(Base.top, Base.front); "parallel Z" r=2 → Body1  ok"#))
    }

    @Test("Chamfers take a distance and shells open faces")
    func chamferAndShell() async throws {
        let harness = try await harnessWithBase()

        let chamfer = try await harness.call(
            "add_feature", ["type": "chamfer", "body": "Body1", "edges": ["circular"], "distance": "1"])
        let shell = try await harness.call(
            "add_feature", ["name": "Hollow", "type": "shell", "body": "Body1", "faces": ["Base.top"], "thickness": 2])

        #expect(chamfer.success)
        #expect(chamfer.message.contains("Chamfer1: failed: No edge matches the filter 'circular'."))
        #expect(shell.message.contains("+ Hollow  shell Body1 open at Base.top t=2 → Body1  ok"))
    }

    @Test("Missing or misplaced references and sizes are refused")
    func refusals() async throws {
        let harness = try await harnessWithBase()

        #expect(
            try await harness.refused("add_feature", ["type": "fillet", "body": "Body1", "radius": 2])
                == "A fillet needs 'edges', a non-empty list of edge names or filters; call find_geometry to see them.")
        #expect(
            try await harness.refused("add_feature", ["type": "fillet", "body": "Body1", "edges": [], "radius": 2])
                != nil)
        #expect(
            try await harness.refused(
                "add_feature", ["type": "shell", "body": "Body1", "edges": ["parallel Z"], "thickness": 2])
                == "A shell does not take 'edges'; it takes 'faces'.")
        #expect(
            try await harness.refused(
                "add_feature", ["type": "chamfer", "body": "Body1", "edges": ["parallel Z"], "radius": 2])
                == "A chamfer does not take 'radius'; it takes distance.")
        #expect(
            try await harness.refused(
                "add_feature", ["type": "fillet", "body": "Body1", "edges": ["parallel Z"]])
                == "A fillet needs 'radius'.")
        #expect(
            try await harness.refused(
                "add_feature", ["type": "box", "width": 1, "depth": 1, "height": 1, "edges": ["x"]])
                == "A box does not take 'edges'.")
        #expect(
            try await harness.refused("add_feature", ["type": "fillet", "body": "Body1", "edges": [3], "radius": 1])
                == "'edges' must be an array of edge names or filters.")
    }

    @Test("Editing the radius keeps the edges")
    func editRadius() async throws {
        let harness = try await harnessWithBase()
        _ = try await harness.call(
            "add_feature", ["name": "Round", "type": "fillet", "body": "Body1", "edges": ["parallel Z"], "radius": 2])

        let result = try await harness.call("edit_feature", ["feature": "Round", "radius": 3])

        #expect(result.success)
        #expect(
            harness.document.parts[0].features[1].kind
                == .fillet(FilletFeature(body: "Body1", edges: [.filter("parallel Z")], radius: 3)))
    }

    @Test("Renaming a feature rewrites the references to its faces")
    func renameRewritesReferences() async throws {
        let harness = try await harnessWithBase()
        _ = try await harness.call(
            "add_feature",
            ["name": "Round", "type": "fillet", "body": "Body1", "edges": ["edge(Base.front, Base.top)"], "radius": 2])

        let result = try await harness.call("rename_feature", ["feature": "Base", "new_name": "Plate"])

        #expect(result.success)
        #expect(
            harness.document.parts[0].features[1].kind
                == .fillet(FilletFeature(body: "Body1", edges: [.name("edge(Plate.front, Plate.top)")], radius: 2)))
        #expect(
            result.message.contains(
                """
                Geometry references updated:
                  Round now refers to edge(Plate.front, Plate.top) (was edge(Base.front, Base.top))
                """))
        #expect(!result.message.contains("failed"))
    }

    @Test("Deleting the feature whose faces a fillet uses leaves the fillet failing with the candidates")
    func deleteLeavesFailingReference() async throws {
        let harness = try await harnessWithBase()
        _ = try await harness.call(
            "add_feature",
            [
                "name": "Cap", "type": "box", "width": 10, "depth": 10, "height": 5,
                "placement": ["translation": ["z": 10]], "operation": "join", "body": "Body1",
            ])
        _ = try await harness.call(
            "add_feature",
            ["name": "Round", "type": "fillet", "body": "Body1", "edges": ["edge(Cap.front, Cap.top)"], "radius": 1])

        let result = try await harness.call("delete_feature", ["feature": "Cap"])

        #expect(result.success)
        #expect(result.message.contains("Round: ok → failed: No face is named 'Cap.front'"))
    }
}
