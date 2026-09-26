import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("add_feature")
struct AddFeatureToolTests {
    @Test("A box with expressions reports its status, the body and the new listing line")
    func box() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())

        let result = try await harness.call(
            "add_feature", ["name": "Base", "type": "box", "width": "width", "depth": "depth", "height": "t"])

        #expect(result.success)
        #expect(harness.commits == ["Add Base"])
        #expect(
            result.message == """
                Added Base to part Plate
                Base: ok
                Bodies:
                  Body1 (Plate): valid closed solid, 6 faces, 12 edges, volume 24000 mm³, bounds (0, 0, 0) to (60, 40, 10)
                Listing changes:
                  - (no features)
                  + Base  box width×depth×t at origin → Body1  ok
                """)
    }

    @Test("A placed cylinder cuts an existing body")
    func cutCylinder() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())
        _ = try await harness.call("add_feature", ["type": "box", "width": 60, "depth": 40, "height": 10])

        let result = try await harness.call(
            "add_feature",
            [
                "name": "Hole", "type": "cylinder", "radius": "hole_r", "height": "t",
                "placement": ["translation": ["x": "width / 2", "y": 20]], "operation": "cut", "body": "Body1",
            ])

        #expect(result.success)
        #expect(harness.features() == ["Box1", "Hole"])
        #expect(
            harness.document.parts[0].features[1].kind
                == .primitive(
                    PrimitiveFeature(
                        .cylinder(radius: "hole_r", height: "t"),
                        placement: Placement(translation: Vector3("width / 2", 20, 0)), operation: .cut("Body1"))))
        #expect(result.message.contains("Hole: ok"))
        #expect(result.message.contains("Body1 (Plate): valid closed solid, 6 faces, 12 edges, volume 23773.125 mm³"))
    }

    @Test("Default names count up per type, and translations may be given as [x, y, z]")
    func defaultsAndArrays() async throws {
        let harness = Harness()

        _ = try await harness.call("add_feature", ["type": "sphere", "radius": 2])
        _ = try await harness.call(
            "add_feature",
            [
                "type": "sphere", "radius": 1,
                "placement": [
                    "translation": [1, 2, "3"], "rotationAxis": ["x": 1, "y": 0, "z": 0], "rotationDegrees": 90,
                ],
            ])
        _ = try await harness.call(
            "add_feature", ["type": "boolean", "operation": "union", "body": "Body1", "tools": ["Body2"]])
        _ = try await harness.call(
            "add_feature", ["type": "transform", "body": "Body1", "placement": ["translation": ["z": 5]]])

        #expect(harness.features() == ["Sphere1", "Sphere2", "Boolean1", "Transform1"])
        #expect(
            harness.document.parts[0].features[1].kind
                == .primitive(
                    PrimitiveFeature(
                        .sphere(radius: 1),
                        placement: Placement(
                            translation: Vector3(1, 2, 3), rotationAxis: Vector3(1, 0, 0), rotationDegrees: 90))))
        #expect(
            harness.document.parts[0].features[3].kind
                == .transform(TransformFeature(body: "Body1", placement: Placement(translation: Vector3(0, 0, 5)))))
        #expect(harness.session.result?.parts[0].features.map(\.status) == [.ok, .ok, .ok, .ok])
    }

    @Test("Inserting a new body before others renumbers the references that follow")
    func insertRenumbers() async throws {
        let harness = Harness()
        _ = try await harness.call("add_feature", ["name": "A", "type": "box", "width": 10, "depth": 10, "height": 10])
        _ = try await harness.call(
            "add_feature", ["name": "Cut", "type": "sphere", "radius": 1, "operation": "cut", "body": "Body1"])

        let result = try await harness.call(
            "add_feature", ["name": "First", "type": "sphere", "radius": 3, "before": "A"])

        #expect(result.success)
        #expect(harness.features() == ["First", "A", "Cut"])
        #expect(harness.document.parts[0].features[2].kind.bodyReferences == ["Body2"])
        #expect(result.message.contains("Body references renumbered:\n  Cut now refers to Body2 (was Body1)"))
        #expect(harness.session.result?.parts[0].features.map(\.status) == [.ok, .ok, .ok])
    }

    @Test("'after' inserts right after the named feature")
    func insertAfter() async throws {
        let harness = Harness()
        _ = try await harness.call("add_feature", ["name": "A", "type": "sphere", "radius": 1])
        _ = try await harness.call("add_feature", ["name": "B", "type": "sphere", "radius": 1])

        _ = try await harness.call("add_feature", ["name": "C", "type": "transform", "body": "Body1", "after": "A"])

        #expect(harness.features() == ["A", "C", "B"])
    }

    @Test("Wrong or missing fields are refused with a precise message")
    func refusals() async throws {
        let harness = Harness(Fixtures.plate())
        func refused(_ arguments: [String: JSONValue]) async throws -> String? {
            try await harness.refused("add_feature", arguments)
        }

        #expect(
            try await refused(["radius": 1])
                == "Missing 'type'. Types: box, cylinder, sphere, cone, torus, boolean, transform, fillet, chamfer, shell, extrude, revolve."
        )
        #expect(
            try await refused(["type": "wedge"])
                == "Unknown type 'wedge'. Types: box, cylinder, sphere, cone, torus, boolean, transform, fillet, chamfer, shell, extrude, revolve."
        )
        #expect(try await refused(["type": "box", "width": 1, "depth": 1]) == "A box needs 'height'.")
        #expect(
            try await refused(["type": "box", "width": 1, "depth": 1, "height": 1, "radius": 2])
                == "A box does not take 'radius'; it takes width, depth, height.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "body": "Body1"])
                == "'body' only applies to join, cut and intersect; newBody creates its own body.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "operation": "cut"])
                == "Operation cut needs 'body', the body to cut.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "operation": "union"])
                == "A solid's 'operation' is one of newBody, join, cut, intersect, not 'union'.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "tools": ["Body1"]]) == "A sphere does not take 'tools'.")
        #expect(
            try await refused(["type": "boolean", "operation": "subtract", "body": "Body1"])
                == "A boolean needs 'tools', a non-empty list of bodies.")
        #expect(
            try await refused(["type": "boolean", "operation": "cut", "body": "Body1", "tools": ["Body2"]])
                == "A boolean needs 'operation': union, subtract, intersect.")
        #expect(
            try await refused([
                "type": "boolean", "operation": "union", "body": "Body1", "tools": ["Body2"], "radius": 1,
            ]) == "A boolean does not take 'radius'.")
        #expect(
            try await refused(["type": "transform", "body": "Body1", "operation": "cut"])
                == "A transform does not take 'operation'.")
        #expect(try await refused(["type": "transform"]) == "A transform needs 'body', the body to move.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "name": "Base"])
                == "Part Plate already has a feature named 'Base'.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "name": "my ball"])?.hasPrefix(
                "'my ball' is not a valid feature name") == true)
        #expect(
            try await refused(["type": "sphere", "radius": 1, "before": "Nope"])
                == "No feature named 'Nope' in part Plate.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "before": "Base", "after": "Hole"])
                == "Give 'before' or 'after', not both.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "part": "Lid"]) == "No part named 'Lid'. Parts: Plate.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "placement": ["position": [1, 2, 3]]])
                == "Unknown argument 'position'. Accepted: translation, rotationAxis, rotationDegrees.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "placement": ["translation": [1, 2]]])
                == "'placement.translation' must have x, y and z.")
        #expect(
            try await refused(["type": "box", "width": "wdth", "depth": 1, "height": "t +"]) == """
                Nothing changed, because these expressions would not evaluate:
                  Box1.width = wdth: unknown parameter 'wdth'
                  Box1.height = t +: syntax error: unexpected end of expression
                """)
    }

    @Test("A document with several parts needs the part named")
    func severalParts() async throws {
        let harness = Harness(CADDocument(parts: [Part(name: "A"), Part(name: "B")]))

        #expect(
            try await harness.refused("add_feature", ["type": "sphere", "radius": 1])
                == "The document has several parts (A, B); say which one with 'part'.")
        #expect(try await harness.call("add_feature", ["type": "sphere", "radius": 1, "part": "B"]).success)
        #expect(harness.features(1) == ["Sphere1"])
    }

    @Test("A feature that fails to build is still added, and its failure is reported")
    func failingFeature() async throws {
        let harness = Harness()

        let result = try await harness.call(
            "add_feature", ["type": "cone", "bottomRadius": 2, "topRadius": 2, "height": 3])

        #expect(result.success)
        #expect(result.message.contains("Cone1: failed: cone radii must differ"))
        #expect(result.message.contains("Bodies: none"))
    }
}
