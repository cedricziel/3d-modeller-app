import CADModel
import CADModelKernel
import Foundation
import Testing

@Suite("Naming with the OCCT kernel")
struct NamingIntegrationTests {
    let engine = RebuildEngine(kernel: OCCTGeometryKernel())

    private func approx(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-4) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= tolerance * max(1, abs(b))
    }

    private static let plate = Feature(
        name: "Plate", kind: .primitive(PrimitiveFeature(.box(width: 60, depth: 40, height: 10))))
    private static let hole = Feature(
        name: "Hole",
        kind: .primitive(
            PrimitiveFeature(
                .cylinder(radius: 5, height: 20), placement: Placement(translation: Vector3(30, 20, -5)),
                operation: .cut("Body1"))))

    private func rebuild(_ features: [Feature]) async throws -> PartResult {
        try #require(try await engine.rebuild(CADDocument(parts: [Part(name: "P", features: features)])).parts.first)
    }

    @Test("Filleting the edges picked by a filter rounds the two +X corners")
    func filletByFilter() async throws {
        let part = try await rebuild([
            Self.plate, Self.hole,
            Feature(
                name: "Round",
                kind: .fillet(FilletFeature(body: "Body1", edges: [.filter("parallel Z and farthest +X")], radius: 3))),
        ])

        #expect(part.features.map(\.status) == [.ok, .ok, .ok])
        let corners = 2 * 9 * (1 - Double.pi / 4) * 10
        #expect(approx(part.bodies.first?.metrics?.volume, 60 * 40 * 10 - .pi * 25 * 10 - corners))
        let names = Set(part.bodies.first?.topology?.faces.flatMap(\.names) ?? [])
        #expect(names.isSuperset(of: ["Round.face[0]", "Round.face[1]", "Hole.side", "Plate.top"]))
    }

    @Test("An edge filter on a drilled plate leaves out the hole's seam")
    func filterSkipsSeam() async throws {
        let part = try await rebuild([
            Self.plate, Self.hole,
            Feature(
                name: "Round", kind: .fillet(FilletFeature(body: "Body1", edges: [.filter("parallel Z")], radius: 3))),
        ])

        #expect(part.features[2].status == .ok)
        let corners = 4 * 9 * (1 - Double.pi / 4) * 10
        #expect(approx(part.bodies.first?.metrics?.volume, 60 * 40 * 10 - .pi * 25 * 10 - corners))
    }

    @Test("Filleting the hole's seam by name fails instead of leaving it sharp")
    func seamByNameFails() async throws {
        let part = try await rebuild([
            Self.plate, Self.hole,
            Feature(
                name: "Round",
                kind: .fillet(
                    FilletFeature(
                        body: "Body1", edges: [.name("edge(Plate.front, Plate.top)"), .name("edge(Hole.side)")],
                        radius: 1))),
        ])

        guard case .failed(.kernel(let message)) = part.features[2].status else {
            Issue.record("expected a kernel failure, got \(part.features[2].status)")
            return
        }
        #expect(message.contains("leave out seams"))
    }

    @Test("A shell the geometry cannot take fails; the rest still builds")
    func shellTooThick() async throws {
        let part = try await rebuild([
            Self.plate,
            Feature(
                name: "Hollow", kind: .shell(ShellFeature(body: "Body1", faces: [.name("Plate.top")], thickness: 25))),
            Feature(name: "Other", kind: .primitive(PrimitiveFeature(.sphere(radius: 1)))),
        ])

        guard case .failed(.kernel) = part.features[1].status else {
            Issue.record("expected a kernel failure, got \(part.features[1].status)")
            return
        }
        #expect(part.features[2].status == .ok)
    }

    @Test("Chamfering the hole's top edge by name")
    func chamferHoleByName() async throws {
        let part = try await rebuild([
            Self.plate, Self.hole,
            Feature(
                name: "Bevel",
                kind: .chamfer(ChamferFeature(body: "Body1", edges: [.name("edge(Hole.side, Plate.top)")], distance: 1))
            ),
        ])

        #expect(part.features[2].status == .ok)
        let ring = Double.pi * (5 + 1.0 / 3) * 1
        #expect(approx(part.bodies.first?.metrics?.volume, 60 * 40 * 10 - .pi * 25 * 10 - ring))
    }

    @Test("Shelling a box open at the top")
    func shellOpenTop() async throws {
        let part = try await rebuild([
            Self.plate,
            Feature(
                name: "Hollow", kind: .shell(ShellFeature(body: "Body1", faces: [.name("Plate.top")], thickness: 2))),
        ])

        #expect(part.features[1].status == .ok)
        #expect(approx(part.bodies.first?.metrics?.volume, 60 * 40 * 10 - 56 * 36 * 8))
    }

    @Test("A slot splits the top; the bare name becomes ambiguous and a piece name still works")
    func namesSurviveBooleanSplit() async throws {
        let slot = Feature(
            name: "Slot",
            kind: .primitive(
                PrimitiveFeature(
                    .box(width: 4, depth: 50, height: 5), placement: Placement(translation: Vector3(28, -5, 6)),
                    operation: .cut("Body1"))))
        func round(_ reference: String) -> Feature {
            Feature(
                name: "Round",
                kind: .fillet(
                    FilletFeature(body: "Body1", edges: [.name("edge(Plate.front, \(reference))")], radius: 1)))
        }

        let ambiguous = try await rebuild([Self.plate, slot, round("Plate.top")])
        guard case .failed(.reference(let message)) = ambiguous.features[2].status else {
            Issue.record("expected an ambiguous reference, got \(ambiguous.features[2].status)")
            return
        }
        #expect(message.hasPrefix("'edge(Plate.front, Plate.top)' matches 2 edges; name one of them: "))
        #expect(message.contains("edge(Plate.front, Plate.top)[0]"))

        let piece = try await rebuild([Self.plate, slot, round("Plate.top[1]")])
        #expect(piece.features[2].status == .ok)
    }

    @Test("Names follow a body through a transform")
    func filletAfterTransform() async throws {
        let part = try await rebuild([
            Self.plate,
            Feature(
                name: "Turn",
                kind: .transform(
                    TransformFeature(
                        body: "Body1",
                        placement: Placement(rotationAxis: Vector3(0, 0, 1), rotationDegrees: 90)))),
            Feature(
                name: "Round",
                kind: .fillet(FilletFeature(body: "Body1", edges: [.name("edge(Plate.front, Plate.top)")], radius: 2))),
        ])

        #expect(part.features.map(\.status) == [.ok, .ok, .ok])
        let wall = part.bodies.first?.topology?.faces.first { $0.names == ["Plate.front"] }
        #expect(approx(wall?.normal?.x, 1))
    }

    @Test("A fillet the geometry cannot take fails; the rest still builds")
    func filletTooLarge() async throws {
        let part = try await rebuild([
            Self.plate,
            Feature(
                name: "Round", kind: .fillet(FilletFeature(body: "Body1", edges: [.filter("parallel Z")], radius: 30))),
            Feature(name: "Other", kind: .primitive(PrimitiveFeature(.sphere(radius: 1)))),
        ])

        guard case .failed(.kernel) = part.features[1].status else {
            Issue.record("expected a kernel failure, got \(part.features[1].status)")
            return
        }
        #expect(part.features[2].status == .ok)
    }
}
