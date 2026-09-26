import CADModel
import CADModelKernel
import CADModelSolvers
import Foundation
import Testing
import simd

@Suite("Exports of solved assemblies")
struct SolvedExportTests {
    private static func box(_ name: String, _ w: Scalar, _ d: Scalar, _ h: Scalar) -> Feature {
        Feature(name: name, kind: .primitive(PrimitiveFeature(.box(width: w, depth: d, height: h))))
    }

    /// The motion tests' lid, hinged on the box's back top edge and opened to 90°, starting from a placement the
    /// solve moves it away from.
    private func openLid() -> CADDocument {
        let box = Part(name: "Box", features: [Self.box("Box", 60, 40, 30)])
        let lid = Part(name: "Lid", features: [Self.box("Lid", 60, 40, 5)])
        let base = Instance(name: "Base", part: box.id, grounded: true)
        let top = Instance(name: "Lid", part: lid.id, placement: Placement(translation: Vector3(0, 0, 30)))
        let hinge = Joint(
            name: "Hinge", kind: .revolute,
            a: JointFrameRef(instance: base.id, face: .name("Box.left"), offset: JointOffset(x: 20, y: -15)),
            b: JointFrameRef(instance: top.id, face: .name("Lid.left"), offset: JointOffset(x: 20, y: 2.5)),
            flip: true, limits: JointLimits(min: 0, max: 110), value: 90)
        return CADDocument(parts: [box, lid], assembly: Assembly(instances: [base, top], joints: [hinge]))
    }

    private func temporaryFile(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cadmodel-solved-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: name)
    }

    @Test("A joint-moved instance is exported where the solve put it")
    func solvedTransformRoundTrips() async throws {
        let model = try await RebuildEngine(kernel: OCCTGeometryKernel(), assemblySolver: OndselAssemblySolver())
            .build(openLid())
        let lid = try #require(model.result.assembly?.instance(named: "Lid"))
        let lidID = lid.id
        let step = try temporaryFile("lid.step")
        let threeMF = try temporaryFile("lid.3mf")
        let expectedMin = SIMD3<Double>(0, 40, 30)
        let expectedMax = SIMD3<Double>(60, 45, 70)

        _ = try model.geometry.export(.instance(lidID), of: model.result, as: .step, to: step)
        _ = try model.geometry.export(.instance(lidID), of: model.result, as: .threeMF, to: threeMF)
        let stepBounds = try #require(try OCCTGeometryKernel.inspectSTEP(at: step).bounds)
        let item = try #require(try ThreeMFReader.read(Data(contentsOf: threeMF)).items.first)

        #expect(lid.movedByJoints)
        #expect(simd_distance(stepBounds.min, expectedMin) < 1e-3)
        #expect(simd_distance(stepBounds.max, expectedMax) < 1e-3)
        #expect(simd_distance(item.bounds.min, expectedMin) < 0.02)
        #expect(simd_distance(item.bounds.max, expectedMax) < 0.02)
    }
}
