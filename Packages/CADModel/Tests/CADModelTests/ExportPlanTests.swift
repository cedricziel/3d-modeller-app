@testable import CADModel
import Foundation
import Testing

@Suite("Export plan")
struct ExportPlanTests {
    let engine = RebuildEngine(kernel: FakeKernel())

    private func box(_ name: String) -> Feature {
        Feature(name: name, kind: .primitive(PrimitiveFeature(.box(width: 10, depth: 10, height: 10))))
    }

    private func built(_ result: RebuildResult) -> Set<BodyKey> {
        Set(result.parts.flatMap { part in part.bodies.map { BodyKey(part: part.id, body: $0.name) } })
    }

    private func at(_ x: Double) -> Placement {
        Placement(translation: Vector3(.number(x), 0, 0))
    }

    @Test("Without an assembly the document exports each part at its own coordinates")
    func partsWithoutAssembly() async throws {
        let document = CADDocument(parts: [
            Part(name: "Plate", features: [box("A")]), Part(name: "Pin", features: [box("B")]),
        ])
        let result = try await engine.rebuild(document)

        let scene = try ExportPlan.scene(.document, in: result, built: built(result))

        #expect(scene.products.map(\.name) == ["Plate", "Pin"])
        #expect(scene.products.map(\.color) == [ExportPalette.color(0), ExportPalette.color(1)])
        #expect(scene.occurrences.isEmpty)
        #expect(scene.skipped.isEmpty)
    }

    @Test("With instances the document exports the assembly, one product per part")
    func assemblyUsesInstances() async throws {
        let plate = Part(name: "Plate", features: [box("A")])
        let pin = Part(name: "Pin", features: [box("B")])
        let instances = [
            Instance(name: "Base", part: plate.id, grounded: true),
            Instance(name: "Pin1", part: pin.id, placement: at(20)),
            Instance(name: "Pin2", part: pin.id, placement: at(40)),
        ]
        let result = try await engine.rebuild(
            CADDocument(parts: [plate, pin], assembly: Assembly(instances: instances)))

        let scene = try ExportPlan.scene(.document, in: result, built: built(result))
        let translations = scene.occurrences.map(\.transform.translation.x)

        #expect(scene.name == "Assembly")
        #expect(scene.products.map(\.name) == ["Plate", "Pin"])
        #expect(scene.occurrences.map(\.name) == ["Base", "Pin1", "Pin2"])
        #expect(scene.occurrences.map(\.product) == [0, 1, 1])
        #expect(translations == [0, 20, 40])
        #expect(scene.products[1].bodies.map(\.body) == [BodyKey(part: pin.id, body: "Body1")])
    }

    @Test("An instance of one body of a multi-body part exports only that body")
    func instanceBodySelection() async throws {
        let plate = Part(name: "Plate", features: [box("A"), box("B")])
        let lid = Instance(name: "Lid", part: plate.id, body: "Body2")
        let result = try await engine.rebuild(
            CADDocument(parts: [plate], assembly: Assembly(instances: [lid])))

        let scene = try ExportPlan.scene(.instance(lid.id), in: result, built: built(result))

        #expect(scene.products.map(\.name) == ["Plate/Body2"])
        #expect(scene.products[0].bodies.map(\.name) == ["Body2"])
        #expect(scene.occurrences.map(\.name) == ["Lid"])
    }

    @Test("A part and a body export on their own")
    func partAndBody() async throws {
        let plate = Part(name: "Plate", features: [box("A"), box("B")])
        let result = try await engine.rebuild(CADDocument(parts: [plate]))

        let part = try ExportPlan.scene(.part(plate.id), in: result, built: built(result))
        let body = try ExportPlan.scene(.body(part: plate.id, body: "Body1"), in: result, built: built(result))

        #expect(part.products.map(\.name) == ["Plate"])
        #expect(part.products[0].bodies.map(\.name) == ["Body1", "Body2"])
        #expect(body.products.map(\.name) == ["Plate/Body1"])
        #expect(body.occurrences.isEmpty)
    }

    @Test("Two parts with the same name stay two products")
    func samePartNames() async throws {
        let first = Part(name: "Plate", features: [box("A")])
        let second = Part(name: "Plate", features: [box("B")])
        let instances = [Instance(name: "One", part: first.id), Instance(name: "Two", part: second.id)]
        let result = try await engine.rebuild(
            CADDocument(parts: [first, second], assembly: Assembly(instances: instances)))

        let assembly = try ExportPlan.scene(.document, in: result, built: built(result))
        let parts = try ExportPlan.scene(
            .document, in: RebuildResult(parameters: result.parameters, parts: result.parts, assembly: nil),
            built: built(result))
        let secondKey = BodyKey(part: second.id, body: "Body1")

        #expect(assembly.products.count == 2)
        #expect(assembly.occurrences.map(\.product) == [0, 1])
        #expect(assembly.products[1].bodies.map(\.body) == [secondKey])
        #expect(parts.products.count == 2)
    }

    @Test("A failed instance is left out and named")
    func failedInstanceSkipped() async throws {
        let plate = Part(name: "Plate", features: [box("A")])
        let instances = [
            Instance(name: "Base", part: plate.id), Instance(name: "Lid", part: plate.id, body: "Body9"),
        ]
        let result = try await engine.rebuild(CADDocument(parts: [plate], assembly: Assembly(instances: instances)))

        let scene = try ExportPlan.scene(.document, in: result, built: built(result))

        #expect(scene.occurrences.map(\.name) == ["Base"])
        #expect(scene.skipped.count == 1)
        #expect(scene.skipped.first?.hasPrefix("Lid (failed: ") == true)
    }

    @Test("A body the kernel did not build is left out and named")
    func unbuiltBodySkipped() async throws {
        let plate = Part(name: "Plate", features: [box("A"), box("B")])
        let result = try await engine.rebuild(CADDocument(parts: [plate]))
        let missing = BodyKey(part: plate.id, body: "Body2")

        let scene = try ExportPlan.scene(.part(plate.id), in: result, built: built(result).subtracting([missing]))

        #expect(scene.products[0].bodies.map(\.name) == ["Body1"])
        #expect(scene.skipped == ["Plate/Body2 (not built)"])
    }

    @Test("With nothing left to export the error names why")
    func nothingToExport() async throws {
        let plate = Part(name: "Plate", features: [box("A")])
        let lid = Instance(name: "Lid", part: plate.id, body: "Body9")
        let result = try await engine.rebuild(CADDocument(parts: [plate], assembly: Assembly(instances: [lid])))

        #expect {
            try ExportPlan.scene(.document, in: result, built: built(result))
        } throws: { error in
            (error as? ExportError)?.description.hasPrefix("Nothing to export: Lid (failed: ") == true
        }
    }

    @Test("Unknown parts, bodies and instances are refused, naming what exists")
    func unknownTargets() async throws {
        let plate = Part(name: "Plate", features: [box("A")])
        let result = try await engine.rebuild(CADDocument(parts: [plate]))
        let keys = built(result)

        #expect(throws: ExportError.self) { try ExportPlan.scene(.part(UUID()), in: result, built: keys) }
        #expect(throws: ExportError("Plate has no body named Body7; bodies: Body1")) {
            try ExportPlan.scene(.body(part: plate.id, body: "Body7"), in: result, built: keys)
        }
        #expect(throws: ExportError.self) { try ExportPlan.scene(.instance(UUID()), in: result, built: keys) }
    }
}
