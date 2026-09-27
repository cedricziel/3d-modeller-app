@testable import CADModel
import Foundation
import Testing
import simd

@Suite("Model export")
struct ModelExportTests {
    let kernel = FakeKernel()

    private func temporaryFile(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cadmodel-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: name)
    }

    private func twoPins() async throws -> RebuiltModel {
        let pin = Part(
            name: "Pin",
            features: [Feature(name: "A", kind: .primitive(PrimitiveFeature(.box(width: 1, depth: 1, height: 1))))])
        let instances = [
            Instance(name: "Pin1", part: pin.id, placement: Placement(translation: Vector3(20, 0, 0))),
            Instance(name: "Pin2", part: pin.id, placement: Placement(translation: Vector3(40, 0, 0))),
        ]
        return try await RebuildEngine(kernel: kernel).build(
            CADDocument(parts: [pin], assembly: Assembly(instances: instances)))
    }

    @Test("STL writes every occurrence's triangles where the assembly places them")
    func stl() async throws {
        let model = try await twoPins()
        let url = try temporaryFile("pins.stl")

        let summary = try model.geometry.export(.document, of: model.result, as: .stl, to: url, tolerance: 0.05)
        let contents = try STLReader.read(Data(contentsOf: url))
        let expected = Bounds(min: SIMD3(20, 0, 0), max: SIMD3(41, 1, 0))

        #expect(contents.triangleCount == 2)
        #expect(contents.bounds == expected)
        #expect(summary.triangleCount == 2)
        #expect(summary.products == ["Pin"])
        #expect(summary.occurrences == ["Pin1", "Pin2"])
        #expect(summary.bytes == 184)
        #expect(kernel.calls.contains("mesh tolerance 0.05"))
    }

    @Test("3MF writes one object placed twice")
    func threeMF() async throws {
        let model = try await twoPins()
        let url = try temporaryFile("pins.3mf")

        _ = try model.geometry.export(.document, of: model.result, as: .threeMF, to: url)
        let contents = try ThreeMFReader.read(Data(contentsOf: url))

        #expect(contents.items.count == 2)
        #expect(contents.items.map(\.object) == [2, 2])
        #expect(contents.items.map(\.bounds.min.x) == [20, 40])
    }

    @Test("A kernel without a STEP writer says so")
    func stepUnsupported() async throws {
        let model = try await twoPins()
        let url = try temporaryFile("pins.step")

        #expect(throws: ExportError("this geometry kernel cannot write STEP")) {
            try model.geometry.export(.document, of: model.result, as: .step, to: url)
        }
    }

    @Test("A tolerance of zero is refused")
    func badTolerance() async throws {
        let model = try await twoPins()
        let url = try temporaryFile("pins.stl")

        #expect(throws: ExportError.self) {
            try model.geometry.export(.document, of: model.result, as: .stl, to: url, tolerance: 0)
        }
    }
}
