import Foundation
import Testing

@testable import CADModel

@Suite("Rebuild engine solids")
struct SolidsTests {
    private func box(_ name: String, _ size: Scalar, operation: SolidOperation = .newBody) -> Feature {
        Feature(
            name: name,
            kind: .primitive(PrimitiveFeature(.box(width: size, depth: 1, height: 1), operation: operation)))
    }

    @Test("Solids are each part's final bodies, without consumed tools or failed features")
    func finalBodies() async throws {
        let document = CADDocument(parts: [
            Part(
                name: "P",
                features: [
                    box("A", 10), box("B", 2), box("C", 0),
                    Feature(
                        name: "U",
                        kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: ["Body2"]))),
                ]),
            Part(name: "Q", features: [box("D", 3)]),
        ])

        let solids = try await RebuildEngine(kernel: FakeKernel()).solids(of: document)

        #expect(solids.map { "\($0.part)/\($0.name)" } == ["P/Body1", "Q/Body1"])
        #expect(solids.map(\.body.volume) == [12, 3])
    }
}
