@testable import CADModel
import Foundation
import Testing

func roundTrip(_ kind: FeatureKind) throws -> FeatureKind {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try JSONDecoder().decode(FeatureKind.self, from: encoder.encode(kind))
}

func decodeKind(_ json: String) throws -> FeatureKind {
    try JSONDecoder().decode(FeatureKind.self, from: Data(json.utf8))
}

let rectangleSketch = SketchFeature(
    plane: .base(.xy),
    entities: [
        SketchEntity(name: "line1", .line(start: SketchPoint2(0, 0), end: SketchPoint2(60, 0))),
        SketchEntity(name: "line2", .line(start: SketchPoint2(60, 0), end: SketchPoint2(60, 40))),
        SketchEntity(name: "line3", .line(start: SketchPoint2(60, 40), end: SketchPoint2(0, 40))),
        SketchEntity(name: "line4", .line(start: SketchPoint2(0, 40), end: SketchPoint2(0, 0))),
    ],
    constraints: [
        SketchConstraint(name: "c1", .coincident, points: ["line1.end", "line2.start"]),
        SketchConstraint(name: "c2", .coincident, points: ["line2.end", "line3.start"]),
        SketchConstraint(name: "c3", .coincident, points: ["line3.end", "line4.start"]),
        SketchConstraint(name: "c4", .coincident, points: ["line4.end", "line1.start"]),
        SketchConstraint(name: "c5", .horizontal, entities: ["line1"]),
        SketchConstraint(name: "c6", .horizontal, entities: ["line3"]),
        SketchConstraint(name: "c7", .vertical, entities: ["line2"]),
        SketchConstraint(name: "c8", .vertical, entities: ["line4"]),
        SketchConstraint(name: "c9", .fixed, points: ["line1.start"], at: [0, 0]),
        SketchConstraint(name: "c10", .distance, points: ["line1.start", "line1.end"], value: "width"),
        SketchConstraint(name: "c11", .distance, points: ["line2.start", "line2.end"], value: 40),
    ]
)

@Suite("Sketch coding")
struct SketchCodingTests {
    @Test("A sketch with every entity kind and constraint field survives a round trip")
    func sketchRoundTrip() throws {
        var sketch = rectangleSketch
        sketch.plane = .face(body: "Body1", face: .name("Box1.top"), offset: "t / 2")
        sketch.entities += [
            SketchEntity(name: "circle1", .circle(center: SketchPoint2(30, 20), radius: 5), construction: true),
            SketchEntity(name: "arc1", .arc(center: SketchPoint2(0, 0), radius: 5, startAngle: 0, endAngle: 90)),
            SketchEntity(name: "point1", .point(SketchPoint2(1, 2))),
        ]
        sketch.constraints.append(SketchConstraint(name: "c12", .angle, entities: ["line1", "line2"], value: 90))
        let kind = FeatureKind.sketch(sketch)
        #expect(try roundTrip(kind) == kind)
    }

    @Test("Extrudes and revolves survive a round trip with every extent and axis")
    func sketchBasedRoundTrip() throws {
        let extents: [ExtrudeExtent] = [
            .distance(10), .symmetric("t"), .throughAll, .upToFace(body: "Body1", face: .filter("normal +Z")),
        ]
        for extent in extents {
            let kind = FeatureKind.extrude(
                ExtrudeFeature(
                    sketch: "Sketch1", regions: ["circle1"], extent: extent, reversed: true, operation: .cut("Body1")
                )
            )
            #expect(try roundTrip(kind) == kind)
        }
        let axes: [RevolveAxis] = [
            .sketchLine("line5"), .x, .y, .z, .edge(body: "Body1", edge: .name("edge(A.b, A.c)")),
        ]
        for axis in axes {
            let kind = FeatureKind.revolve(
                RevolveFeature(sketch: "Sketch1", axis: axis, angle: 90, operation: .newBody))
            #expect(try roundTrip(kind) == kind)
        }
    }

    @Test("Minimal forms decode to the defaults")
    func defaults() throws {
        let sketch = try decodeKind(
            """
            {"type": "sketch", "plane": {"base": "XZ"},
             "entities": [{"name": "line1", "type": "line", "start": [0, 0], "end": [1, 2]}],
             "constraints": [{"name": "c1", "type": "horizontal", "entities": ["line1"]}]}
            """
        )
        #expect(
            sketch
                == .sketch(
                    SketchFeature(
                        plane: .base(.xz),
                        entities: [
                            SketchEntity(name: "line1", .line(start: SketchPoint2(0, 0), end: SketchPoint2(1, 2)))
                        ],
                        constraints: [SketchConstraint(name: "c1", .horizontal, entities: ["line1"])]
                    )
                )
        )
        let extrude = try decodeKind(#"{"type": "extrude", "sketch": "Sketch1", "extent": {"type": "throughAll"}}"#)
        #expect(
            extrude
                == .extrude(
                    ExtrudeFeature(
                        sketch: "Sketch1", regions: [], extent: .throughAll, reversed: false, operation: .newBody)
                )
        )
        let revolve = try decodeKind(#"{"type": "revolve", "sketch": "S", "axis": {"global": "Z"}}"#)
        #expect(revolve == .revolve(RevolveFeature(sketch: "S", axis: .z, angle: 360, operation: .newBody)))
    }

    @Test("Unknown entity types and axes are refused")
    func refusals() {
        #expect(throws: DecodingError.self) {
            try decodeKind(
                #"{"type": "sketch", "plane": {"base": "XY"}, "entities": [{"name": "e", "type": "spline"}]}"#)
        }
        #expect(throws: DecodingError.self) {
            try decodeKind(#"{"type": "revolve", "sketch": "S", "axis": {"global": "W"}}"#)
        }
    }

    @Test("Only newBody extrudes and revolves create bodies; sketches create none")
    func createdBodies() {
        let part = Part(
            name: "P",
            features: [
                Feature(name: "Sketch1", kind: .sketch(rectangleSketch)),
                Feature(
                    name: "Pad",
                    kind: .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance(5), operation: .newBody))
                ),
                Feature(
                    name: "Pocket",
                    kind: .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance(2), operation: .cut("Body1")))
                ),
                Feature(
                    name: "Spin",
                    kind: .revolve(RevolveFeature(sketch: "Sketch1", axis: .z, angle: 360, operation: .newBody))
                ),
            ]
        )
        #expect(part.createdBodies() == ["Body1": part.features[1].id, "Body2": part.features[3].id])
        let affected = part.affectedBodies()
        #expect(affected[part.features[0].id] == nil)
        #expect(affected[part.features[2].id] == "Body1")
    }

    @Test("Body and geometry references include planes, up-to faces and axes")
    func references() {
        var sketch = rectangleSketch
        sketch.plane = .face(body: "Body1", face: .name("Box1.top"))
        #expect(FeatureKind.sketch(sketch).bodyReferences == ["Body1"])
        #expect(FeatureKind.sketch(sketch).geometryReferences == [.name("Box1.top")])
        let extrude = FeatureKind.extrude(
            ExtrudeFeature(
                sketch: "Sketch1", extent: .upToFace(body: "Body2", face: .name("Box2.top")), operation: .join("Body1")
            )
        )
        #expect(extrude.bodyReferences == ["Body1", "Body2"])
        let revolve = FeatureKind.revolve(
            RevolveFeature(
                sketch: "S", axis: .edge(body: "Body3", edge: .name("e")), angle: 360, operation: .newBody
            )
        )
        #expect(revolve.bodyReferences == ["Body3"])
        #expect(revolve.sketchReference == "S")
    }

    @Test("Renaming a feature rewrites sketch references, face names and body references")
    func renames() {
        var extrude = FeatureKind.extrude(
            ExtrudeFeature(
                sketch: "Sketch1", extent: .upToFace(body: "Body2", face: .name("Sketch1x.top")),
                operation: .join("Body1")
            )
        )
        extrude.renameFeatureReferences("Sketch1", to: "Base")
        guard case let .extrude(renamed) = extrude else { Issue.record("kind changed"); return }
        #expect(renamed.sketch == "Base")
        #expect(renamed.extent == .upToFace(body: "Body2", face: .name("Sketch1x.top")))

        var fillet = FeatureKind.fillet(
            FilletFeature(body: "Body1", edges: [.name("edge(Pad.side[Sketch1.line1], Pad.end)")], radius: 1)
        )
        fillet.renameFeatureReferences("Sketch1", to: "Base")
        #expect(fillet.geometryReferences == [.name("edge(Pad.side[Base.line1], Pad.end)")])

        extrude.renameBodyReferences { $0 == "Body2" ? "Body7" : $0 }
        #expect(extrude.bodyReferences == ["Body1", "Body7"])
    }
}
