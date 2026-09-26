import CADModel
import Foundation
import Testing

@Suite("Model geometry")
struct ModelGeometryTests {
    private let document = CADDocument(parts: [
        Part(
            name: "P",
            features: [
                Feature(name: "A", kind: .primitive(PrimitiveFeature(.box(width: 1, depth: 2, height: 3)))),
                Feature(name: "B", kind: .primitive(PrimitiveFeature(.box(width: 1, depth: 1, height: 1)))),
            ])
    ])

    @Test("The build keeps each body under its part and name for measuring")
    func measuresBuiltBodies() async throws {
        let model = try await RebuildEngine(kernel: FakeKernel()).build(document)
        let part = document.parts[0].id
        let (a, b) = (BodyKey(part: part, body: "Body1"), BodyKey(part: part, body: "Body2"))

        #expect(model.result.bodies.map(\.name) == ["Body1", "Body2"])
        #expect(try model.geometry.distance(.body(a), .body(b)).distance == 5)
        #expect(try model.geometry.bounds(of: .face(a, 0)).max == SIMD3(repeating: 6))
        #expect(try model.geometry.interference(a, b) == 0)
    }

    @Test("Points are measured without the kernel; an unknown body is named in the error")
    func pointsAndUnknownBodies() async throws {
        let geometry = try await RebuildEngine(kernel: FakeKernel()).build(document).geometry

        #expect(try geometry.distance(.point(.zero), .point(SIMD3(3, 4, 0))).distance == 5)
        #expect(throws: MeasureError("Body9 was not built")) {
            try geometry.distance(.point(.zero), .body(BodyKey(part: document.parts[0].id, body: "Body9")))
        }
        #expect(throws: MeasureError.self) { try ModelGeometry.empty.bounds(of: .point(.zero)) }
    }

    @Test("Parts that share a name keep their bodies apart")
    func partsWithTheSameName() async throws {
        let box = { (size: Scalar) in
            Feature(name: "A", kind: .primitive(PrimitiveFeature(.box(width: size, depth: size, height: size))))
        }
        let document = CADDocument(parts: [Part(name: "P", features: [box(1)]), Part(name: "P", features: [box(3)])])
        let geometry = try await RebuildEngine(kernel: FakeKernel()).build(document).geometry
        let first = BodyKey(part: document.parts[0].id, body: "Body1")
        let second = BodyKey(part: document.parts[1].id, body: "Body1")

        #expect(try geometry.bounds(of: .face(first, 0)).max == SIMD3(repeating: 1))
        #expect(try geometry.bounds(of: .face(second, 0)).max == SIMD3(repeating: 27))
    }
}
