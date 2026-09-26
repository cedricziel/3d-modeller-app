import CADModel
import CADModelKernel
import Foundation
import Testing
import simd

@Suite("Export round trips through Open CASCADE")
struct ExportRoundTripTests {
    let engine = RebuildEngine(kernel: OCCTGeometryKernel())

    private func temporaryFile(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cadmodel-roundtrip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: name)
    }

    private static let plate = Part(
        name: "Plate",
        features: [Feature(name: "Box", kind: .primitive(PrimitiveFeature(.box(width: 60, depth: 40, height: 10))))])
    private static let pin = Part(
        name: "Pin",
        features: [Feature(name: "Rod", kind: .primitive(PrimitiveFeature(.cylinder(radius: 5, height: 20))))])

    private func assembly() -> CADDocument {
        let instances = [
            Instance(name: "Base", part: Self.plate.id, grounded: true),
            Instance(name: "Pin1", part: Self.pin.id, placement: Placement(translation: Vector3(10, 10, 10))),
            Instance(
                name: "Pin2", part: Self.pin.id,
                placement: Placement(
                    translation: Vector3(40, 20, 10), rotationAxis: Vector3(1, 0, 0), rotationDegrees: 90)),
        ]
        return CADDocument(parts: [Self.plate, Self.pin], assembly: Assembly(instances: instances))
    }

    private func volumes(_ result: RebuildResult) -> Double {
        result.bodies.reduce(0) { $0 + ($1.metrics?.volume ?? 0) }
    }

    private func instanceBounds(_ result: RebuildResult) throws -> Bounds {
        let metrics = try #require(result.assembly?.instances.compactMap { $0.bodies.first?.metrics })
        let first = try #require(metrics.first)
        return metrics.reduce(Bounds(min: first.boundsMin, max: first.boundsMax)) {
            Bounds(min: simd_min($0.min, $1.boundsMin), max: simd_max($0.max, $1.boundsMax))
        }
    }

    private func close(_ a: Bounds?, _ b: Bounds, _ tolerance: Double) -> Bool {
        guard let a else { return false }
        return simd_distance(a.min, b.min) <= tolerance && simd_distance(a.max, b.max) <= tolerance
    }

    @Test("Parts without an assembly come back as one solid each")
    func partsStep() async throws {
        let model = try await engine.build(CADDocument(parts: [Self.plate, Self.pin]))
        let url = try temporaryFile("parts.step")

        _ = try model.geometry.export(.document, of: model.result, as: .step, to: url)
        let inspection = try OCCTGeometryKernel.inspectSTEP(at: url)
        let expected = volumes(model.result)

        #expect(inspection.solidCount == 2)
        #expect(abs(inspection.volume - expected) <= 1e-3 * expected)
        #expect(inspection.names.contains("Plate"))
        #expect(inspection.names.contains("Pin"))
    }

    @Test("An assembly comes back with every instance where the rebuild placed it")
    func assemblyStep() async throws {
        let model = try await engine.build(assembly())
        let url = try temporaryFile("assembly.step")

        let summary = try model.geometry.export(.document, of: model.result, as: .step, to: url)
        let inspection = try OCCTGeometryKernel.inspectSTEP(at: url)
        let pinVolume = Double.pi * 25 * 20
        let expected = 60.0 * 40 * 10 + 2 * pinVolume
        let bounds = try instanceBounds(model.result)

        #expect(summary.products == ["Plate", "Pin"])
        #expect(summary.occurrences == ["Base", "Pin1", "Pin2"])
        #expect(inspection.solidCount == 3)
        #expect(abs(inspection.volume - expected) <= 1e-3 * expected)
        #expect(close(inspection.bounds, bounds, 1e-3))
        #expect(inspection.names.contains("Pin2"))
    }

    @Test("STL comes back with the rebuild's bounds")
    func stlBounds() async throws {
        let model = try await engine.build(assembly())
        let url = try temporaryFile("assembly.stl")

        let summary = try model.geometry.export(.document, of: model.result, as: .stl, to: url)
        let contents = try STLReader.read(Data(contentsOf: url))
        let bounds = try instanceBounds(model.result)

        #expect(contents.triangleCount > 0)
        #expect(contents.triangleCount == summary.triangleCount)
        #expect(close(contents.bounds, bounds, 0.02))
    }

    @Test("3MF comes back with the rebuild's bounds for each instance")
    func threeMFBounds() async throws {
        let model = try await engine.build(assembly())
        let url = try temporaryFile("assembly.3mf")

        _ = try model.geometry.export(.document, of: model.result, as: .threeMF, to: url)
        let contents = try ThreeMFReader.read(Data(contentsOf: url))
        let instances = try #require(model.result.assembly?.instances)

        #expect(contents.items.count == 3)
        for (item, instance) in zip(contents.items, instances) {
            let metrics = try #require(instance.bodies.first?.metrics)
            #expect(
                close(item.bounds, Bounds(min: metrics.boundsMin, max: metrics.boundsMax), 0.02), "\(instance.name)")
        }
    }

    @Test("A single body exports on its own")
    func bodyStep() async throws {
        let model = try await engine.build(CADDocument(parts: [Self.plate, Self.pin]))
        let url = try temporaryFile("pin.step")

        _ = try model.geometry.export(
            .body(part: Self.pin.id, body: "Body1"), of: model.result, as: .step, to: url)
        let inspection = try OCCTGeometryKernel.inspectSTEP(at: url)

        #expect(inspection.solidCount == 1)
        #expect(inspection.names.contains("Pin"))
    }
}
