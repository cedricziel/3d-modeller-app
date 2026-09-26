import Foundation
import Testing

@testable import CADModel

@Suite("Body naming")
struct BodyNamingTests {
    private func box(_ name: String, _ operation: SolidOperation = .newBody, suppressed: Bool = false) -> Feature {
        Feature(
            name: name, suppressed: suppressed,
            kind: .primitive(PrimitiveFeature(.box(width: 1, depth: 1, height: 1), operation: operation)))
    }

    @Test("Bodies are named by the ordinal of their creating feature, counting suppressed ones")
    func createdBodies() {
        let a = box("A")
        let b = box("B", suppressed: true)
        let c = box("C", .cut("Body1"))
        let d = box("D")
        let part = Part(name: "P", features: [a, b, c, d])

        #expect(part.createdBodies() == ["Body1": a.id, "Body2": b.id, "Body3": d.id])
    }

    @Test("Each feature names the body it creates or changes, matching the rebuild")
    func affectedBodies() async throws {
        let a = box("A")
        let b = box("B", .join("Body1"))
        let c = Feature(name: "C", kind: .transform(TransformFeature(body: "Body1", placement: .identity)))
        let d = box("D")
        let e = Feature(name: "E", kind: .boolean(BooleanFeature(operation: .union, target: "Body2", tools: ["Body1"])))
        let part = Part(name: "P", features: [a, b, c, d, e])
        let rebuilt = try await RebuildEngine(kernel: FakeKernel()).rebuild(CADDocument(parts: [part]))

        let expected: [UUID: String] = [
            a.id: "Body1", b.id: "Body1", c.id: "Body1", d.id: "Body2", e.id: "Body2",
        ]
        #expect(part.affectedBodies() == expected)
        #expect(Dictionary(uniqueKeysWithValues: rebuilt.parts[0].features.map { ($0.id, $0.body) }) == expected)
    }

    @Test("Body references are listed and renamed for every feature kind")
    func references() {
        var cut = FeatureKind.primitive(PrimitiveFeature(.sphere(radius: 1), operation: .cut("Body1")))
        var boolean = FeatureKind.boolean(
            BooleanFeature(operation: .subtract, target: "Body1", tools: ["Body2", "Body3"]))
        var transform = FeatureKind.transform(TransformFeature(body: "Body2", placement: .identity))
        var fresh = FeatureKind.primitive(PrimitiveFeature(.sphere(radius: 1)))

        #expect(cut.bodyReferences == ["Body1"])
        #expect(boolean.bodyReferences == ["Body1", "Body2", "Body3"])
        #expect(transform.bodyReferences == ["Body2"])
        #expect(fresh.bodyReferences.isEmpty)

        let rename: (String) -> String = { $0 == "Body1" ? "BodyA" : $0 + "x" }
        cut.renameBodyReferences(rename)
        boolean.renameBodyReferences(rename)
        transform.renameBodyReferences(rename)
        fresh.renameBodyReferences(rename)

        #expect(cut.bodyReferences == ["BodyA"])
        #expect(boolean.bodyReferences == ["BodyA", "Body2x", "Body3x"])
        #expect(transform.bodyReferences == ["Body2x"])
        #expect(fresh == .primitive(PrimitiveFeature(.sphere(radius: 1))))
    }
}
