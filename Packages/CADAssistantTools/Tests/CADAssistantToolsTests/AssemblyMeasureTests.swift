@testable import CADAssistantTools
import CADModel
import CADModelKernel
import Foundation
import SwiftUIAssistant
import Testing

@MainActor
@Suite("Measuring, finding and rendering across instances")
struct AssemblyMeasureTests {
    private func plates(lidAt z: Double, kernel: any GeometryKernel = FakeKernel()) async throws -> Harness {
        let plate = Part(name: "Plate", features: [Fixtures.box("Box", 60, 40, 10)])
        let document = CADDocument(
            parts: [plate],
            assembly: Assembly(instances: [
                Instance(name: "Base", part: plate.id, grounded: true),
                Instance(name: "Lid", part: plate.id, placement: Placement(translation: Vector3(0, 0, .number(z)))),
            ])
        )
        let harness = Harness(document, kernel: kernel)
        try await harness.session.rebuild()
        return harness
    }

    private func measure(_ harness: Harness, _ kind: String, _ a: JSONValue, _ b: JSONValue? = nil) async throws
        -> ToolExecutionResult
    {
        var arguments: [String: JSONValue] = ["kind": .string(kind), "a": a]
        if let b {
            arguments["b"] = b
        }
        return try await harness.call("measure", arguments)
    }

    @Test("A face of an instance is measured where the instance puts it")
    func measureInstanceFace() async throws {
        let result = try await measure(plates(lidAt: 20), "size", ["instance": "Lid", "face": "Box.top"])

        #expect(result.message.hasPrefix("Box.top of Lid: plane, area 2400 mm², centre (30, 20, 30), normal (0, 0, 1)"))
    }

    @Test("Stacked instances touch, sunk ones overlap, lifted ones keep a clearance")
    func interferenceBetweenInstances() async throws {
        let pair: (JSONValue, JSONValue) = (["instance": "Base"], ["instance": "Lid"])
        let touching = try await measure(
            plates(lidAt: 10, kernel: OCCTGeometryKernel()), "interference", pair.0, pair.1)
        let sunk = try await measure(plates(lidAt: 5, kernel: OCCTGeometryKernel()), "interference", pair.0, pair.1)
        let lifted = try await measure(plates(lidAt: 30, kernel: OCCTGeometryKernel()), "interference", pair.0, pair.1)

        #expect(touching.message == "Base and Lid touch without overlapping")
        #expect(sunk.message == "Base and Lid overlap by 12000 mm³")
        #expect(lifted.message == "Base and Lid do not overlap; clearance 20 mm")
    }

    @Test("A part body and an instance can be measured against each other")
    func mixedOperand() async throws {
        let result = try await measure(plates(lidAt: 20), "distance", ["body": "Body1"], ["instance": "Lid"])

        #expect(result.message.hasPrefix("Distance 10 mm between Body1 (Plate) and Lid"))
    }

    @Test("Instance operands are refused with the choices")
    func refusals() async throws {
        let harness = try await plates(lidAt: 20)

        #expect(
            try await harness.refused("measure", ["kind": "size", "a": ["part": "Plate", "instance": "Lid"]])
                == "'a' names a part and an instance; give one of them."
        )
        #expect(
            try await harness.refused("measure", ["kind": "size", "a": ["instance": "Top"]])
                == "No instance named 'Top'. Instances: Base, Lid."
        )
        #expect(
            try await harness.refused("measure", ["kind": "size", "a": ["instance": "Lid", "body": "Body3"]])
                == "Lid has no body named Body3. Bodies: Body1."
        )
    }

    @Test("An instance with several bodies needs 'body' to be measured whole")
    func severalBodies() async throws {
        let part = Part(name: "P", features: [Fixtures.box("A", 1, 1, 1), Fixtures.box("B", 2, 2, 2)])
        let harness = Harness(
            CADDocument(parts: [part], assembly: Assembly(instances: [Instance(name: "Two", part: part.id)]))
        )
        try await harness.session.rebuild()

        #expect(
            try await harness.refused("measure", ["kind": "size", "a": ["instance": "Two"]])
                == "Two shows bodies Body1, Body2; add 'body'."
        )
        #expect(
            try await measure(harness, "size", ["instance": "Two", "body": "Body2"]).message.hasPrefix("Two/Body2: "))
    }

    @Test("find_geometry lists an instance's faces in assembly coordinates")
    func findGeometryOnInstance() async throws {
        let result = try await plates(lidAt: 20).call(
            "find_geometry", ["instance": "Lid", "kind": "faces", "filter": "normal +Z"]
        )

        #expect(
            result.message.hasPrefix(
                "Lid (Plate/Body1): 1 of 6 faces match \"normal +Z\"\n  Box.top  plane  centre (30, 20, 30)"))
    }

    @Test("render_views shows the assembly by default, the parts on request")
    func renderAssembly() async throws {
        let harness = try await plates(lidAt: 20)

        let assembly = try await harness.call("render_views", ["views": ["iso"]])
        let parts = try await harness.call("render_views", ["views": ["iso"], "show": "parts"])

        #expect(
            assembly.message.hasPrefix("Rendered 1 view, 512 × 512 px each: Base (Plate) blue, Lid (Plate) orange."))
        #expect(parts.message.hasPrefix("Rendered 1 view, 512 × 512 px each: Body1 (Plate) blue."))
        #expect(
            try await Harness().refused("render_views", ["show": "assembly"])
                == "The document has no instances to show; use show: parts."
        )
    }
}
