import CADModel
import CADModelKernel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("measure")
struct MeasureToolTests {
    private func harness() async throws -> Harness {
        let harness = Harness()
        _ = try await harness.call(
            "add_feature", ["name": "Base", "type": "box", "width": 60, "depth": 40, "height": 10])
        _ = try await harness.call(
            "add_feature",
            ["name": "Pin", "type": "cylinder", "radius": 2, "height": 5, "placement": ["translation": [100, 0, 0]]])
        return harness
    }

    private func measure(_ harness: Harness, _ kind: String, _ a: JSONValue, _ b: JSONValue? = nil) async throws
        -> ToolExecutionResult
    {
        var arguments: [String: JSONValue] = ["kind": .string(kind), "a": a]
        if let b { arguments["b"] = b }
        return try await harness.call("measure", arguments)
    }

    @Test("A body's size lists volume, area, bounds, extent and counts")
    func bodySize() async throws {
        let result = try await measure(harness(), "size", ["body": "Body1"])

        #expect(result.success)
        #expect(
            result.message
                == "Body1 (Plate): volume 24000 mm³, area 6800 mm², bounds (0, 0, 0) to (60, 40, 10), "
                + "extent 60 × 40 × 10, 6 faces, 12 edges")
    }

    @Test("A face's size lists its type, area, centre, normal and bounds; an edge's its length and ends")
    func faceAndEdgeSize() async throws {
        let harness = try await harness()

        let face = try await measure(harness, "size", ["body": "Body1", "face": "Base.top"])
        let edge = try await measure(harness, "size", ["body": "Body1", "edge": "edge(Base.front, Base.top)"])

        #expect(face.message.hasPrefix("Base.top (Body1): plane, area 2400 mm², centre (30, 20, 10), normal (0, 0, 1)"))
        #expect(face.message.contains(", bounds "))
        #expect(
            edge.message == "edge(Base.front, Base.top) (Body1): line, length 60 mm, from (0, 0, 10) to (60, 0, 10)")
    }

    @Test("Angles between face normals, between edges, and between an edge and a face")
    func angles() async throws {
        let harness = try await harness()
        let top: JSONValue = ["body": "Body1", "face": "Base.top"]

        let faces = try await measure(harness, "angle", top, ["body": "Body1", "face": "Base.front"])
        let opposite = try await measure(harness, "angle", top, ["body": "Body1", "face": "Base.bottom"])
        let edges = try await measure(
            harness, "angle", ["body": "Body1", "edge": "edge(Base.front, Base.top)"],
            ["body": "Body1", "edge": "edge(Base.left, Base.top)"])
        let mixed = try await measure(harness, "angle", ["body": "Body1", "edge": "edge(Base.front, Base.top)"], top)

        #expect(faces.message == "Angle between the normals of Base.top (Body1) and Base.front (Body1): 90°")
        #expect(opposite.message.hasSuffix(": 180°"))
        #expect(
            edges.message
                == "Angle between edge(Base.front, Base.top) (Body1) and edge(Base.left, Base.top) (Body1): 90°")
        #expect(
            mixed.message == "Angle between edge(Base.front, Base.top) (Body1) and the plane of Base.top (Body1): 0°")
    }

    @Test("Distance gives the gap and the closest points")
    func distance() async throws {
        let result = try await measure(harness(), "distance", ["body": "Body1"], ["body": "Body2"])

        #expect(result.success)
        #expect(result.message.hasPrefix("Distance 40 mm between Body1 (Plate) and Body2 (Plate); closest points "))
    }

    @Test("Operands must be a body, one face or edge of a body, or a point")
    func operandRefusals() async throws {
        let harness = try await harness()

        #expect(
            try await harness.refused("measure", ["kind": "size", "a": "Body1"])?
                .hasPrefix("'a' must be an object such as {\"body\": \"Body1\"}") == true)
        #expect(
            try await harness.refused("measure", ["kind": "size", "a": [:]])?
                .hasPrefix("'a' needs a 'body' or a 'point'") == true)
        #expect(
            try await harness.refused(
                "measure",
                ["kind": "size", "a": ["body": "Body1", "face": "Base.top", "edge": "edge(Base.front, Base.top)"]])
                == "'a' names a face and an edge; measure one of them.")
        #expect(
            try await harness.refused(
                "measure", ["kind": "distance", "a": ["point": [0, 0, 0], "body": "Body1"], "b": ["body": "Body1"]])
                == "'a' is a point, which stands alone; drop 'part', 'body', 'face' and 'edge'.")
        #expect(
            try await harness.refused("measure", ["kind": "size", "a": ["body": "Body7"]])
                == "Part Plate has no body named 'Body7'. Bodies: Body1, Body2.")
        #expect(
            try await harness.refused("measure", ["kind": "size", "a": ["body": "Body1"], "b": ["body": "Body2"]])
                == "size measures one thing; drop 'b'.")
        #expect(
            try await harness.refused("measure", ["kind": "distance", "a": ["body": "Body1"]])
                == "distance needs 'b'.")
        #expect(
            try await harness.refused("measure", ["kind": "volume", "a": ["body": "Body1"]])
                == "'kind' is distance, angle, size or interference, not 'volume'.")
    }

    @Test("A reference that matches several faces is refused with the matches")
    func ambiguousOperand() async throws {
        let message = try await harness().refused(
            "measure", ["kind": "size", "a": ["body": "Body1", "face": "type plane"]])

        #expect(
            message
                == "'a': 'type plane' matches 6 faces of Body1 (Plate): Base.left, Base.right, Base.front, Base.back, "
                + "Base.bottom, Base.top. Measure one of them.")
    }

    @Test("Angles take planar faces and straight edges only")
    func angleRefusals() async throws {
        let harness = try await harness()
        let top: JSONValue = ["body": "Body1", "face": "Base.top"]

        #expect(
            try await harness.refused(
                "measure", ["kind": "angle", "a": ["body": "Body2", "face": "Pin.side"], "b": top])
                == "Pin.side (Body2) is a cylinder face; angle takes planar faces and straight edges.")
        #expect(
            try await harness.refused("measure", ["kind": "angle", "a": ["point": [0, 0, 0]], "b": top])
                == "point (0, 0, 0) is a point; angle takes planar faces and straight edges.")
        #expect(
            try await harness.refused("measure", ["kind": "angle", "a": ["body": "Body1"], "b": top])
                == "Body1 (Plate) is a body; angle takes planar faces and straight edges.")
    }

    @Test("Interference takes two bodies")
    func interferenceRefusals() async throws {
        #expect(
            try await harness().refused(
                "measure",
                ["kind": "interference", "a": ["body": "Body1", "face": "Base.top"], "b": ["body": "Body2"]])
                == "interference compares two bodies; give 'a' and 'b' as {\"body\": …} without a face, edge or point.")
    }

    @Test("On the real kernel: hole-to-wall distance, overlap volume and clearance")
    func realKernel() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "Plate")]), kernel: OCCTGeometryKernel())
        let tools = Dictionary(uniqueKeysWithValues: CADTools.all(session: session).map { ($0.name, $0) })
        let add = { (arguments: [String: JSONValue]) in
            _ = try await tools["add_feature"]!.execute(arguments: arguments)
        }
        try await add(["name": "Plate", "type": "box", "width": 60, "depth": 40, "height": 10])
        try await add([
            "name": "Hole", "type": "cylinder", "radius": 2.75, "height": 10,
            "placement": ["translation": ["x": 30, "y": 20]], "operation": "cut", "body": "Body1",
        ])
        try await add([
            "name": "A", "type": "box", "width": 10, "depth": 10, "height": 10,
            "placement": ["translation": [100, 0, 0]],
        ])
        try await add([
            "name": "B", "type": "box", "width": 10, "depth": 10, "height": 10,
            "placement": ["translation": [105, 0, 0]],
        ])
        try await add([
            "name": "C", "type": "box", "width": 10, "depth": 10, "height": 10,
            "placement": ["translation": [200, 0, 0]],
        ])
        let measure = tools["measure"]!

        let wall = try await measure.execute(arguments: [
            "kind": "distance", "a": ["body": "Body1", "face": "Hole.side"],
            "b": ["body": "Body1", "face": "Plate.left"],
        ])
        let overlap = try await measure.execute(arguments: [
            "kind": "interference", "a": ["body": "Body2"], "b": ["body": "Body3"],
        ])
        let apart = try await measure.execute(arguments: [
            "kind": "interference", "a": ["body": "Body2"], "b": ["body": "Body4"],
        ])
        let rim = try await measure.execute(arguments: [
            "kind": "angle", "a": ["body": "Body1", "edge": "circular and farthest +Z"],
            "b": ["body": "Body1", "face": "Plate.top"],
        ])

        #expect(wall.message.hasPrefix("Distance 27.25 mm between Hole.side (Body1) and Plate.left (Body1)"))
        #expect(overlap.message == "Body2 (Plate) and Body3 (Plate) overlap by 500 mm³")
        #expect(apart.message == "Body2 (Plate) and Body4 (Plate) do not overlap; clearance 90 mm")
        #expect(
            rim.message
                == "edge(Hole.side, Plate.top) (Body1) is a circle edge; angle takes planar faces and straight edges.")
    }
}
