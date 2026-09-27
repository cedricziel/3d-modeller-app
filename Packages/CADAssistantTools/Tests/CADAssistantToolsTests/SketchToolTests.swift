import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("add_sketch, edit_sketch, get_sketch")
struct SketchToolTests {
    nonisolated static let rectangle: JSONValue = [
        ["type": "line", "start": [0, 0], "end": [60, 0]],
        ["type": "line", "start": [60, 0], "end": [60, 40]],
        ["type": "line", "start": [60, 40], "end": [0, 40]],
        ["type": "line", "start": [0, 40], "end": [0, 0]],
    ]

    nonisolated static let rectangleConstraints: JSONValue = [
        ["type": "coincident", "points": ["line1.end", "line2.start"]],
        ["type": "horizontal", "entities": ["line1"]],
        ["type": "distance", "points": ["line1.start", "line1.end"], "value": "width"],
        ["type": "fixed", "points": ["line1.start"], "at": [0, 0]],
        ["type": "angle", "entities": ["line1", "line2"], "value": 90],
    ]

    @Test("A sketch gets entity and constraint names, a listing line and a detailed report")
    func addRectangle() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())
        let result = try await harness.call(
            "add_sketch", ["plane": "XY", "entities": Self.rectangle, "constraints": Self.rectangleConstraints])

        #expect(result.success, "\(result.message)")
        #expect(harness.features() == ["Sketch1"])
        guard case .sketch(let sketch) = harness.document.parts[0].features[0].kind else {
            Issue.record("not a sketch")
            return
        }
        #expect(sketch.entities.map(\.name) == ["line1", "line2", "line3", "line4"])
        #expect(sketch.constraints.map(\.name) == ["c1", "c2", "c3", "c4", "c5"])
        #expect(sketch.constraints[3].at == [0, 0])
        #expect(result.message.contains("+ Sketch1  on XY: 4 lines, 5 constraints; 1 region; fully constrained  ok"))
        #expect(
            result.message.contains(
                "Sketch1 on XY (origin (0, 0, 0), x (1, 0, 0), y (0, 1, 0)): fully constrained; 1 region"))
        #expect(result.message.contains("  line1  line (0, 0) to (60, 0)"))
        #expect(result.message.contains("  c3  distance line1.start, line1.end = width (60)"))
        #expect(result.message.contains("  c4  fixed line1.start at (0, 0)"))
        #expect(result.message.contains("  c5  angle line1, line2 = 90°"))
        #expect(harness.commits == ["Add Sketch1"])
    }

    @Test("Given names are kept and new ones count on from the highest")
    func names() async throws {
        let harness = Harness()
        let result = try await harness.call(
            "add_sketch",
            [
                "name": "Profile", "plane": "XZ", "offset": 5,
                "entities": [
                    ["type": "circle", "name": "circle4", "center": [0, 0], "radius": 3],
                    ["type": "circle", "center": [10, 0], "radius": 3, "construction": true],
                    ["type": "arc", "center": [0, 0], "radius": 8, "startAngle": 0, "endAngle": 180],
                    ["type": "point", "at": [1, 2]],
                ],
                "constraints": [["type": "radius", "entities": ["circle4"], "value": 3, "name": "r"]],
            ])
        #expect(result.success, "\(result.message)")
        guard case .sketch(let sketch) = harness.document.parts[0].features[0].kind else { return }
        #expect(sketch.entities.map(\.name) == ["circle4", "circle5", "arc1", "point1"])
        #expect(sketch.entities[1].construction)
        #expect(sketch.plane == .base(.xz, offset: 5))
        #expect(harness.features() == ["Profile"])
    }

    nonisolated static let refusals: [([String: JSONValue], String)] = [
        (["plane": "XY", "entities": [["type": "spline"]]], "'spline'"),
        (["plane": "XY", "entities": [["type": "line", "start": [0, 0]]]], "needs 'end'"),
        (["plane": "XY", "entities": [["type": "line", "start": [0, 0], "end": [1]]]], "[x, y]"),
        (
            ["plane": "XY", "entities": rectangle, "constraints": [["type": "horizontal", "entities": ["line9"]]]],
            "no entity named 'line9'"
        ),
        (
            [
                "plane": "XY", "entities": rectangle,
                "constraints": [["type": "distance", "points": ["line1.start"], "value": 1]],
            ],
            "needs 2 points"
        ),
        (["plane": "Box9.top", "entities": rectangle], "'body'"),
        (["plane": "XY", "entities": [["type": "line", "name": "a.b", "start": [0, 0], "end": [1, 1]]]], "'a.b'"),
        (["entities": rectangle], "'plane'"),
        (
            [
                "plane": "XY", "entities": rectangle,
                "constraints": [["type": "radius", "entities": ["line1"], "value": 3]],
            ],
            "an arc or a circle"
        ),
    ]

    @Test("Bad sketches are refused before anything changes", arguments: refusals)
    func addSketchRefusals(arguments: [String: JSONValue], expected: String) async throws {
        let harness = Harness()
        let message = try await harness.refused("add_sketch", arguments)
        #expect(message?.contains(expected) == true, "\(message ?? "not refused")")
    }

    @Test("A face plane defaults to the part's only body")
    func faceDefaultsToOnlyBody() async throws {
        let harness = Harness(Fixtures.sketched())
        let result = try await harness.call("add_sketch", ["plane": "Box1.top", "entities": Self.rectangle])
        #expect(result.success, "\(result.message)")
        guard case .sketch(let sketch) = harness.document.parts[0].features.last?.kind else { return }
        #expect(sketch.plane == .face(body: "Body1", face: .name("Box1.top")))
    }

    @Test("edit_sketch adds, updates and removes entities and constraints, and changes values")
    func edit() async throws {
        let harness = Harness(Fixtures.sketched())
        let result = try await harness.call(
            "edit_sketch",
            [
                "sketch": "Sketch1",
                "add_entities": [["type": "circle", "center": [30, 20], "radius": 5]],
                "add_constraints": [["type": "radius", "entities": ["circle1"], "value": "hole_r"]],
                "set_values": ["c2": 80],
                "update_entities": [["name": "line3", "type": "line", "start": [60, 41], "end": [0, 41]]],
            ])
        #expect(result.success, "\(result.message)")
        #expect(result.message.hasPrefix("Edited Sketch1: added circle1, c3; updated line3; set c2 = 80"))
        guard case .sketch(let sketch) = harness.document.parts[0].features[1].kind else { return }
        #expect(sketch.entities.map(\.name) == ["line1", "line2", "line3", "line4", "line5", "circle1"])
        #expect(sketch.constraints[1].value == 80)
        #expect(sketch.constraints[2] == SketchConstraint(name: "c3", .radius, entities: ["circle1"], value: "hole_r"))
        #expect(sketch.entities[2].geometry == .line(start: SketchPoint2(60, 41), end: SketchPoint2(0, 41)))
    }

    @Test("Removing an entity removes the constraints that use it and says so")
    func removeEntityDropsConstraints() async throws {
        let harness = Harness(Fixtures.sketched())
        let result = try await harness.call("edit_sketch", ["sketch": "Sketch1", "remove_entities": ["line1"]])
        #expect(result.success, "\(result.message)")
        #expect(result.message.hasPrefix("Edited Sketch1: removed line1 with c1, c2"))
        guard case .sketch(let sketch) = harness.document.parts[0].features[1].kind else { return }
        #expect(sketch.constraints.isEmpty)
        #expect(sketch.entities.count == 4)
    }

    @Test("A removed entity's name is never handed out again")
    func namesNotReused() async throws {
        let harness = Harness(Fixtures.sketched())
        _ = try await harness.call("edit_sketch", ["sketch": "Sketch1", "remove_entities": ["line5"]])
        let result = try await harness.call(
            "edit_sketch", ["sketch": "Sketch1", "add_entities": [["type": "line", "start": [0, 0], "end": [0, 5]]]])
        #expect(result.success, "\(result.message)")
        guard case .sketch(let sketch) = harness.document.parts[0].features[1].kind else { return }
        #expect(sketch.entities.map(\.name) == ["line1", "line2", "line3", "line4", "line6"])
    }

    @Test("update_entities keeps the construction flag unless given, and refuses a new type")
    func updateKeepsConstruction() async throws {
        let harness = Harness(Fixtures.sketched())
        let result = try await harness.call(
            "edit_sketch",
            [
                "sketch": "Sketch1",
                "update_entities": [["name": "line5", "type": "line", "start": [0, 0], "end": [0, 12]]],
            ])
        #expect(result.success, "\(result.message)")
        guard case .sketch(let sketch) = harness.document.parts[0].features[1].kind else { return }
        #expect(sketch.entities[4].construction)
        let retyped = try await harness.refused(
            "edit_sketch",
            [
                "sketch": "Sketch1",
                "update_entities": [["name": "line5", "type": "circle", "center": [0, 0], "radius": 2]],
            ])
        #expect(retyped?.contains("cannot change line5 from a line to a circle") == true, "\(retyped ?? "")")
    }

    @Test("edit_sketch refuses unknown names, values on constraints without one, and empty edits")
    func editRefusals() async throws {
        let harness = Harness(Fixtures.sketched())
        let unknown = try await harness.refused("edit_sketch", ["sketch": "Sketch1", "remove_constraints": ["c9"]])
        #expect(unknown?.contains("no constraint named 'c9'") == true)
        let noValue = try await harness.refused("edit_sketch", ["sketch": "Sketch1", "set_values": ["c1": 3]])
        #expect(noValue?.contains("c1 (horizontal) takes no value") == true)
        let empty = try await harness.refused("edit_sketch", ["sketch": "Sketch1"])
        #expect(empty?.contains("Give at least one change") == true)
        let notSketch = try await harness.refused("edit_sketch", ["sketch": "Box1", "offset": 1])
        #expect(notSketch?.contains("Box1 is not a sketch") == true)
        let bodyOnBase = try await harness.refused("edit_sketch", ["sketch": "Sketch1", "body": "Body1"])
        #expect(bodyOnBase == "'body' is only for a sketch on a face, not on XY.")
    }

    @Test("get_sketch shows the frame, the entities, the constraints and open ends")
    func getSketch() async throws {
        var document = Fixtures.sketched()
        guard case .sketch(var sketch) = document.parts[0].features[1].kind else { return }
        sketch.entities.remove(at: 3)
        sketch.entities.append(
            SketchEntity(name: "arc1", .arc(center: SketchPoint2(0, 0), radius: 5, startAngle: 0, endAngle: 90)))
        document.parts[0].features[1].kind = .sketch(sketch)
        let harness = Harness(document)
        let result = try await harness.call("get_sketch", ["sketch": "Sketch1"])
        #expect(result.success)
        #expect(
            result.message == """
                Sketch1 on XY (origin (0, 0, 0), x (1, 0, 0), y (0, 1, 0)): fully constrained; no closed profile
                entities:
                  line1  line (0, 0) to (60, 0)
                  line2  line (60, 0) to (60, 40)
                  line3  line (60, 40) to (0, 40)
                  line5  line (0, 0) to (0, 10)  construction
                  arc1  arc centre (0, 0) r=5 from 0° to 90°, (5, 0) to (0, 5)
                constraints:
                  c1  horizontal line1
                  c2  distance line1.start, line1.end = width (60)
                open ends: line1.start (0, 0), line3.end (0, 40), arc1.start (5, 0), arc1.end (0, 5)
                """)
    }
}
