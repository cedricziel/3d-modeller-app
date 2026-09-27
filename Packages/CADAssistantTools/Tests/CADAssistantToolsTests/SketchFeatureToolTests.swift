import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("Extrude and revolve through the feature tools")
struct SketchFeatureToolTests {
    private func added(_ arguments: [String: JSONValue]) async throws -> (FeatureKind, String) {
        let harness = Harness(Fixtures.sketched())
        let result = try await harness.call("add_feature", arguments)
        #expect(result.success, "\(result.message)")
        return (try #require(harness.document.parts[0].features.last).kind, result.message)
    }

    @Test("An extrude by a distance makes a new body and lists compactly")
    func extrudeDistance() async throws {
        let (kind, message) = try await added(["type": "extrude", "sketch": "Sketch1", "distance": 10])
        #expect(kind == .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance(10))))
        #expect(message.contains("+ Extrude1  extrude Sketch1 10 → Body2  ok"))
    }

    @Test("Every extent, regions, reversed and an operation are stored")
    func extents() async throws {
        let symmetric = try await added([
            "type": "extrude", "sketch": "Sketch1", "extent": "symmetric", "distance": "t", "regions": ["line1"],
        ]).0
        #expect(symmetric == .extrude(ExtrudeFeature(sketch: "Sketch1", regions: ["line1"], extent: .symmetric("t"))))
        let through = try await added([
            "type": "extrude", "sketch": "Sketch1", "extent": "throughAll", "operation": "cut", "body": "Body1",
        ]).0
        #expect(through == .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .throughAll, operation: .cut("Body1"))))
        let upTo = try await added([
            "type": "extrude", "sketch": "Sketch1", "extent": "upToFace", "face": "Box1.top", "referenceBody": "Body1",
        ]).0
        #expect(
            upTo
                == .extrude(
                    ExtrudeFeature(sketch: "Sketch1", extent: .upToFace(body: "Body1", face: .name("Box1.top")))))
        let reversed = try await added([
            "type": "extrude", "sketch": "Sketch1", "distance": 3, "reversed": true, "operation": "join",
            "body": "Body1",
        ]).0
        #expect(
            reversed
                == .extrude(
                    ExtrudeFeature(sketch: "Sketch1", extent: .distance(3), reversed: true, operation: .join("Body1"))))
    }

    @Test("Up to a face on the target body needs no reference body")
    func upToFaceOnTarget() async throws {
        let kind = try await added([
            "type": "extrude", "sketch": "Sketch1", "extent": "upToFace", "face": "Box1.top", "operation": "join",
            "body": "Body1",
        ]).0
        #expect(
            kind
                == .extrude(
                    ExtrudeFeature(
                        sketch: "Sketch1", extent: .upToFace(body: "Body1", face: .name("Box1.top")),
                        operation: .join("Body1"))))
    }

    @Test("Revolve axes: a sketch line, a world axis, a body edge")
    func revolveAxes() async throws {
        let line = try await added(["type": "revolve", "sketch": "Sketch1", "axis": "line5", "angle": 90]).0
        #expect(line == .revolve(RevolveFeature(sketch: "Sketch1", axis: .sketchLine("line5"), angle: 90)))
        let z = try await added(["type": "revolve", "sketch": "Sketch1", "axis": "Z"]).0
        #expect(z == .revolve(RevolveFeature(sketch: "Sketch1", axis: .z)))
        let edge = try await added([
            "type": "revolve", "sketch": "Sketch1", "axis": "edge(Box1.front, Box1.left)", "referenceBody": "Body1",
        ]).0
        #expect(
            edge
                == .revolve(
                    RevolveFeature(
                        sketch: "Sketch1", axis: .edge(body: "Body1", edge: .name("edge(Box1.front, Box1.left)")))))
    }

    nonisolated static let refusals: [([String: JSONValue], String)] = [
        (["type": "extrude", "distance": 10], "needs 'sketch'"),
        (["type": "extrude", "sketch": "Sketch1"], "needs 'distance'"),
        (["type": "extrude", "sketch": "Sketch1", "extent": "throughAll"], "through all"),
        (
            [
                "type": "extrude", "sketch": "Sketch1", "extent": "throughAll", "distance": 3, "operation": "cut",
                "body": "Body1",
            ], "'distance'"
        ),
        (["type": "extrude", "sketch": "Sketch1", "distance": 3, "angle": 5], "'angle'"),
        (["type": "extrude", "sketch": "Sketch1", "extent": "upToFace"], "needs 'face'"),
        (["type": "extrude", "sketch": "Sketch1", "extent": "sideways", "distance": 1], "'extent'"),
        (["type": "revolve", "sketch": "Sketch1"], "needs 'axis'"),
        (["type": "revolve", "sketch": "Sketch1", "axis": "Z", "distance": 3], "'distance'"),
        (["type": "sketch"], "add_sketch"),
        (["type": "box", "width": 1, "depth": 1, "height": 1, "sketch": "Sketch1"], "'sketch'"),
    ]

    @Test("Wrong extrude and revolve arguments are refused", arguments: refusals)
    func refused(arguments: [String: JSONValue], expected: String) async throws {
        let harness = Harness(Fixtures.sketched())
        let message = try await harness.refused("add_feature", arguments)
        #expect(message?.contains(expected) == true, "\(message ?? "not refused")")
    }

    @Test("Editing the distance keeps the sketch and the operation")
    func editDistance() async throws {
        let harness = Harness(Fixtures.sketched())
        _ = try await harness.call(
            "add_feature", ["type": "extrude", "sketch": "Sketch1", "distance": 3, "operation": "cut", "body": "Body1"])
        let result = try await harness.call("edit_feature", ["feature": "Extrude1", "distance": 5])
        #expect(result.success, "\(result.message)")
        #expect(
            harness.document.parts[0].features.last?.kind
                == .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance(5), operation: .cut("Body1"))))
        let sketchEdit = try await harness.refused("edit_feature", ["feature": "Sketch1", "distance": 5])
        #expect(sketchEdit?.contains("edit_sketch") == true)
    }

    @Test("An expression that does not evaluate is refused")
    func audit() async throws {
        let harness = Harness(Fixtures.sketched())
        let message = try await harness.refused(
            "add_feature", ["type": "extrude", "sketch": "Sketch1", "distance": "nope"])
        #expect(message?.contains("Extrude1.extent.value = nope") == true, "\(message ?? "")")
    }

    @Test("Sketches, extrudes and revolves each take one listing line")
    func listing() async throws {
        var document = Fixtures.sketched()
        var onFace = Fixtures.rectangleSketch
        onFace.plane = .face(body: "Body1", face: .name("Box1.top"), offset: 2)
        document.parts[0].features += [
            Feature(name: "Sketch2", kind: .sketch(onFace)),
            Feature(
                name: "Pad",
                kind: .extrude(ExtrudeFeature(sketch: "Sketch1", regions: ["line1"], extent: .symmetric(20)))),
            Feature(
                name: "Cut",
                kind: .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .throughAll, operation: .join("Body1")))),
            Feature(
                name: "Up",
                kind: .extrude(
                    ExtrudeFeature(
                        sketch: "Sketch1", extent: .upToFace(body: "Body1", face: .name("Box1.top")), reversed: false))),
            Feature(
                name: "Down", kind: .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance(4), reversed: true))),
            Feature(
                name: "Spin",
                kind: .revolve(RevolveFeature(sketch: "Sketch1", axis: .sketchLine("line5"), operation: .join("Body1")))
            ),
        ]
        let harness = Harness(document)
        try await harness.session.rebuild()
        let lines = harness.session.listing.split(separator: "\n").map(String.init)
        #expect(lines[3] == "  Sketch1  on XY: 5 lines, 2 constraints; 1 region; fully constrained  ok")
        #expect(
            lines[4]
                == "  Sketch2  on Box1.top of Body1, offset 2: 5 lines, 2 constraints; 1 region; fully constrained  ok")
        #expect(lines[5] == "  Pad  extrude Sketch1 regions line1 symmetric 20 → Body2  ok")
        #expect(lines[6] == "  Cut  extrude Sketch1 through all, join Body1 → Body1  ok")
        #expect(lines[7] == "  Up  extrude Sketch1 up to Box1.top of Body1 → Body3  ok")
        #expect(lines[8] == "  Down  extrude Sketch1 4 reversed → Body4  ok")
        #expect(lines[9] == "  Spin  revolve Sketch1 about line5 360°, join Body1 → Body1  ok")
    }

    @Test("Renaming a sketch rewrites the features that use it and reports them")
    func renameSketchRewrites() async throws {
        var document = Fixtures.sketched()
        document.parts[0].features += [
            Feature(name: "Pad", kind: .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance(4)))),
            Feature(
                name: "Round",
                kind: .fillet(
                    FilletFeature(body: "Body2", edges: [.name("edge(Pad.side[Sketch1.line1], Pad.end)")], radius: 1))),
        ]
        let harness = Harness(document)
        let result = try await harness.call("rename_feature", ["feature": "Sketch1", "new_name": "Base"])
        #expect(result.success, "\(result.message)")
        #expect(harness.document.parts[0].features[2].kind.sketchReference == "Base")
        #expect(
            harness.document.parts[0].features[3].kind.geometryReferences == [
                .name("edge(Pad.side[Base.line1], Pad.end)")
            ])
        #expect(result.message.contains("Pad now uses sketch Base (was Sketch1)"))
        #expect(result.message.contains("Round now refers to edge(Pad.side[Base.line1], Pad.end)"))
    }

    @Test("Deleting a sketch that extrudes or revolves use is refused and names them")
    func deleteUsedSketchRefused() async throws {
        var document = Fixtures.sketched()
        document.parts[0].features += [
            Feature(name: "Pad", kind: .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance(4)))),
            Feature(name: "Spin", kind: .revolve(RevolveFeature(sketch: "Sketch1", axis: .x))),
        ]
        let harness = Harness(document)
        let sketch = try #require(document.parts[0].features.first { $0.name == "Sketch1" })

        let message = try await harness.refused("delete_feature", ["feature": "Sketch1"])
        let byID = await harness.session.deleteFeature(id: sketch.id)

        let expected =
            "Nothing changed, because Sketch1 is used by Pad, Spin. Delete or change those features first, or "
            + "suppress Sketch1 instead."
        #expect(message == expected)
        #expect(byID == expected)
        #expect(harness.document == document)
    }
}
