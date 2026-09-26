import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("edit_feature")
struct EditFeatureToolTests {
    private func hole(_ harness: Harness) -> FeatureKind {
        harness.document.parts[0].features[1].kind
    }

    @Test("Only the given fields change; the rest of the placement is kept")
    func partialEdit() async throws {
        let harness = Harness(Fixtures.plate())

        let result = try await harness.call(
            "edit_feature", ["feature": "Hole", "radius": 4, "placement": ["translation": ["x": 12]]]
        )

        #expect(result.success)
        #expect(harness.commits == ["Edit Hole"])
        #expect(
            hole(harness)
                == .primitive(
                    PrimitiveFeature(
                        .cylinder(radius: 4, height: "t"),
                        placement: Placement(translation: Vector3(12, "depth / 2", 0)),
                        operation: .cut("Body1")
                    )
                )
        )
        #expect(result.message.contains("Hole: ok"))
        #expect(
            result.message.contains("- Hole  cylinder r=hole_r h=t at (width / 2, depth / 2, 0), cut Body1 → Body1  ok")
        )
        #expect(result.message.contains("+ Hole  cylinder r=4 h=t at (12, depth / 2, 0), cut Body1 → Body1  ok"))
    }

    @Test("Switching an operation to newBody drops the old target body")
    func toNewBody() async throws {
        let harness = Harness(Fixtures.plate())

        let result = try await harness.call("edit_feature", ["feature": "Hole", "operation": "newBody"])

        #expect(result.success)
        guard case .primitive(let primitive) = hole(harness) else {
            Issue.record("not a primitive")
            return
        }
        #expect(primitive.operation == .newBody)
        #expect(result.message.contains("→ Body2  ok"))
    }

    @Test("Changing the type keeps shared dimensions and needs the new ones")
    func changeType() async throws {
        let harness = Harness(Fixtures.plate())

        #expect(
            try await harness.refused("edit_feature", ["feature": "Base", "type": "cylinder"])
                == "A cylinder needs 'radius'."
        )
        let result = try await harness.call("edit_feature", ["feature": "Base", "type": "cylinder", "radius": 30])

        #expect(result.success)
        #expect(
            harness.document.parts[0].features[0].kind
                == .primitive(PrimitiveFeature(.cylinder(radius: 30, height: "t")))
        )
    }

    @Test("Edits that name nothing, bad expressions and unknown features are refused")
    func refusals() async throws {
        let harness = Harness(Fixtures.plate())

        #expect(
            try await harness.refused("edit_feature", ["feature": "Hole"])?.hasPrefix(
                "Give at least one field to change"
            ) == true
        )
        #expect(
            try await harness.refused("edit_feature", ["feature": "Hole", "radius": .null, "placement": .null])?
                .hasPrefix("Give at least one field to change") == true
        )
        #expect(
            try await harness.refused("edit_feature", ["feature": "Hole", "radius": "hole_rr"])?.contains(
                "Hole.radius = hole_rr: unknown parameter 'hole_rr'"
            ) == true
        )
        #expect(
            try await harness.refused("edit_feature", ["feature": "Holes", "radius": 1])
                == "No feature named 'Holes'. Features by part: Plate: Base, Hole, Pin, BadCone, Merge, Move."
        )
        #expect(
            try await harness.refused("edit_feature", ["feature": "Hole", "name": "Bore"])
                == "Unknown argument 'name'. Accepted: feature, part, type, width, depth, height, radius, bottomRadius, topRadius, majorRadius, minorRadius, distance, thickness, placement, operation, body, tools, edges, faces."
        )
        #expect(
            try await harness.refused("edit_feature", ["feature": "Base", "radius": 3])
                == "A box does not take 'radius'; it takes width, depth, height."
        )
    }

    @Test("Turning a body-creating feature into a join is refused while others use its body")
    func removingUsedBodyRefused() async throws {
        let harness = Harness(Fixtures.plate())

        let message = try await harness.refused(
            "edit_feature", ["feature": "Base", "operation": "join", "body": "Body2"]
        )

        #expect(message?.contains("Hole uses Body1, which Base creates") == true)
        #expect(message?.contains("Merge uses Body1, which Base creates") == true)
        #expect(message?.contains("Move uses Body1, which Base creates") == true)
    }

    @Test("An edit that already failed before but keeps its expression is allowed to change other fields")
    func preexistingFailureAllowed() async throws {
        var document = Fixtures.plate()
        document.parts[0].features[1].kind = .primitive(
            PrimitiveFeature(.cylinder(radius: "missing", height: "t"), operation: .cut("Body1"))
        )
        let harness = Harness(document)

        let result = try await harness.call("edit_feature", ["feature": "Hole", "height": 5])

        #expect(result.success)
        #expect(result.message.contains("Hole: failed: radius: unknown parameter 'missing'"))
    }
}
