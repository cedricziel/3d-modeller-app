import CADModel
import CADModelKernel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("find_geometry")
struct FindGeometryToolTests {
    private func harness() async throws -> Harness {
        let harness = Harness()
        _ = try await harness.call(
            "add_feature", ["name": "Base", "type": "box", "width": 60, "depth": 40, "height": 10])
        return harness
    }

    @Test("Faces are listed with name, type, centre, normal and area")
    func faces() async throws {
        let result = try await harness().call(
            "find_geometry", ["body": "Body1", "kind": "faces", "filter": "normal +Z"])

        #expect(result.success)
        #expect(
            result.message == """
                Body1 (Plate): 1 of 6 faces match "normal +Z"
                  Base.top  plane  centre (30, 20, 10)  normal (0, 0, 1)  area 2400
                """)
    }

    @Test("Edges are listed with their face names, ends and length; no filter lists all")
    func edges() async throws {
        let result = try await harness().call("find_geometry", ["body": "Body1", "kind": "edges"])

        #expect(result.success)
        let lines = result.message.split(separator: "\n")
        #expect(lines.first == "Body1 (Plate): 12 edges")
        #expect(lines.contains("  edge(Base.front, Base.top)  line  from (0, 0, 10) to (60, 0, 10)  length 60"))
    }

    @Test("Unknown bodies, kinds and bad filters are refused with the choices")
    func findGeometryRefusals() async throws {
        let harness = try await harness()

        #expect(
            try await harness.refused("find_geometry", ["body": "Body2", "kind": "faces"])
                == "Part Plate has no body named 'Body2'. Bodies: Body1.")
        #expect(
            try await harness.refused("find_geometry", ["body": "Body1", "kind": "vertices"])
                == "'kind' is faces or edges, not 'vertices'.")
        #expect(
            try await harness.refused("find_geometry", ["body": "Body1", "kind": "edges", "filter": "normal +Z"])?
                .hasPrefix("'normal +Z' is not an edge filter.") == true)
        #expect(
            try await harness.refused("find_geometry", ["body": "Body1", "kind": "faces", "filter": "circular"])
                == nil)
    }

    @Test("On the real kernel a drilled hole shows up as a cylinder and its rim as circles")
    func realKernel() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "Plate")]), kernel: OCCTGeometryKernel())
        let tools = Dictionary(uniqueKeysWithValues: CADTools.all(session: session).map { ($0.name, $0) })
        _ = try await tools["add_feature"]!.execute(arguments: [
            "name": "Plate", "type": "box", "width": 60, "depth": 40, "height": 10,
        ])
        _ = try await tools["add_feature"]!.execute(arguments: [
            "name": "Hole", "type": "cylinder", "radius": 2.75, "height": 10,
            "placement": ["translation": ["x": 30, "y": 20]], "operation": "cut", "body": "Body1",
        ])

        let faces = try await tools["find_geometry"]!.execute(arguments: [
            "body": "Body1", "kind": "faces", "filter": "type cylinder",
        ])
        let edges = try await tools["find_geometry"]!.execute(arguments: [
            "body": "Body1", "kind": "edges", "filter": "circular r=2.75 and farthest +Z",
        ])

        #expect(
            faces.message.contains(
                "Hole.side  cylinder  centre (30, 20, 5)  axis (0, 0, 1) through (30, 20, 0)  r=2.75"))
        #expect(edges.message.contains("edge(Hole.side, Plate.top)  circle  r=2.75  centre (30, 20, 10)"))
    }
}
