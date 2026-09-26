import Foundation
import Testing

@testable import CADModel

@Suite("Fillet, chamfer and shell features")
struct DressUpFeatureTests {
    let kernel = FakeKernel()

    private func base() -> Feature {
        Feature(name: "Base", kind: .primitive(PrimitiveFeature(.box(width: 10, depth: 10, height: 10))))
    }

    private func rebuild(_ features: [Feature], parameters: [Parameter] = []) async throws -> PartResult {
        let result = try await RebuildEngine(kernel: kernel).rebuild(
            CADDocument(parameters: parameters, parts: [Part(name: "P", features: features)]))
        return try #require(result.parts.first)
    }

    @Test("The three kinds round-trip through JSON")
    func coding() throws {
        let kinds: [FeatureKind] = [
            .fillet(
                FilletFeature(
                    body: "Body1", edges: [.name("edge(A.top, A.front)"), .filter("parallel Z")], radius: "r")),
            .chamfer(ChamferFeature(body: "Body1", edges: [.filter("circular r=2")], distance: 1)),
            .shell(ShellFeature(body: "Body2", faces: [.name("A.top")], thickness: 2)),
        ]
        let document = CADDocument(parts: [
            Part(name: "P", features: kinds.enumerated().map { Feature(name: "F\($0.offset)", kind: $0.element) })
        ])
        let json = try document.jsonData()

        #expect(try CADDocument(json: json) == document)
        let text = String(decoding: json, as: UTF8.self)
        #expect(text.contains(#""type" : "fillet""#))
        #expect(text.contains(#""filter" : "parallel Z""#))
        #expect(text.contains(#""thickness" : 2"#))
    }

    @Test("A fillet resolves its references and hands the edge indices and its name to the kernel")
    func filletByName() async throws {
        let part = try await rebuild(
            [
                base(),
                Feature(
                    name: "Round",
                    kind: .fillet(
                        FilletFeature(body: "Body1", edges: [.name("edge(Base.top, Base.front)")], radius: "r"))),
            ], parameters: [Parameter(name: "r", expression: 3)])

        #expect(part.features.map(\.status) == [.ok, .ok])
        #expect(part.features[1].body == "Body1")
        let expected = BodyTopology.box("Base", size: SIMD3(10, 10, 10))
        let index = TopologyNames(expected).edges.firstIndex(of: "edge(Base.front, Base.top)")!
        #expect(kernel.calls.last == "fillet [\(index)] 3 as Round")
        #expect(part.bodies.first?.topology?.faces.last?.names == ["Round.face[0]"])
    }

    @Test("Chamfers and shells take filters and face names")
    func chamferThenShell() async throws {
        let part = try await rebuild([
            base(),
            Feature(
                name: "Bevel",
                kind: .chamfer(
                    ChamferFeature(body: "Body1", edges: [.filter("parallel Z and farthest +X")], distance: 1))),
            Feature(
                name: "Hollow", kind: .shell(ShellFeature(body: "Body1", faces: [.name("Base.top")], thickness: 2))),
        ])

        #expect(part.features.map(\.status) == [.ok, .ok, .ok])
        #expect(kernel.calls.suffix(2).first?.hasPrefix("chamfer [") == true)
        #expect(kernel.calls.suffix(2).first?.hasSuffix("] 1 as Bevel") == true)
        #expect(kernel.calls.last == "shell [5] t2 as Hollow")
    }

    @Test("A reference that matches nothing fails the feature with the candidates; later features still build")
    func missingReference() async throws {
        let part = try await rebuild([
            base(),
            Feature(
                name: "Round",
                kind: .fillet(FilletFeature(body: "Body1", edges: [.name("edge(Base.top, Lid.front)")], radius: 1))),
            Feature(name: "Other", kind: .primitive(PrimitiveFeature(.box(width: 1, depth: 1, height: 1)))),
        ])

        guard case .failed(.reference(let message)) = part.features[1].status else {
            Issue.record("expected a reference failure, got \(part.features[1].status)")
            return
        }
        #expect(message.hasPrefix("No face is named 'Lid.front'"))
        #expect(message.contains("Base.top (plane"))
        #expect(part.features[2].status == .ok)
        #expect(part.bodies.map(\.name) == ["Body1", "Body2"])
    }

    @Test("No references, a bad size or a missing body fail the feature")
    func otherFailures() async throws {
        let part = try await rebuild([
            base(),
            Feature(name: "Empty", kind: .fillet(FilletFeature(body: "Body1", edges: [], radius: 1))),
            Feature(
                name: "Huge", kind: .fillet(FilletFeature(body: "Body1", edges: [.filter("parallel Z")], radius: 500))),
            Feature(
                name: "Nowhere", kind: .shell(ShellFeature(body: "Body9", faces: [.name("Base.top")], thickness: 1))),
            Feature(
                name: "Typo",
                kind: .chamfer(ChamferFeature(body: "Body1", edges: [.filter("parallel Z")], distance: "nope"))),
        ])

        #expect(part.features[1].status == .failed(.reference("no edges are referenced")))
        #expect(part.features[2].status == .failed(.kernel("fillet is too large for the edges")))
        #expect(part.features[3].status == .failed(.unknownBody("Body9")))
        #expect(part.features[4].status == .failed(.expression(field: "distance", .unknownName("nope"))))
    }

    @Test("A dress-up feature on a broken body is skipped")
    func skippedWithBody() async throws {
        let part = try await rebuild([
            Feature(name: "Bad", kind: .primitive(PrimitiveFeature(.box(width: 0, depth: 1, height: 1)))),
            Feature(
                name: "Round", kind: .fillet(FilletFeature(body: "Body1", edges: [.filter("parallel Z")], radius: 1))),
        ])

        #expect(part.features[1].status == .skipped(dependsOn: "Bad"))
    }

    @Test("Renaming a feature rewrites the references to its faces")
    func renameReferences() {
        var kind = FeatureKind.fillet(
            FilletFeature(
                body: "Body1", edges: [.name("edge(Base.top, Base.front)"), .filter("on Base.top")], radius: 1))
        kind.renameFeatureReferences("Base", to: "Plate")

        #expect(kind.geometryReferences == [.name("edge(Plate.top, Plate.front)"), .filter("on Plate.top")])
    }
}
