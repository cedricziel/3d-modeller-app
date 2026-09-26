import CADModel
import CADModelKernel
import Foundation
import Testing

@Suite("OCCT geometry kernel")
struct OCCTGeometryKernelTests {
    let engine = RebuildEngine(kernel: OCCTGeometryKernel())

    private func approx(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-3) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= tolerance * max(1, abs(b))
    }

    @Test("A plate minus a hole, with a failing feature that does not stop the rest")
    func plateWithHole() async throws {
        let json = """
            {"format": 1, "units": "mm",
             "parameters": [{"name": "t", "expression": 10}],
             "parts": [{"name": "Plate", "features": [
               {"name": "Base", "kind": {"type": "box", "width": 60, "depth": 40, "height": "t"}},
               {"name": "Hole", "kind": {"type": "cylinder", "radius": 5, "height": "t",
                 "placement": {"translation": {"x": 30, "y": 20}}, "operation": {"mode": "cut", "body": "Body1"}}},
               {"name": "Bad", "kind": {"type": "cone", "bottomRadius": 3, "topRadius": 3, "height": 5}},
               {"name": "Knob", "kind": {"type": "sphere", "radius": 4,
                 "placement": {"translation": {"x": 10, "y": 10, "z": "t"}}, "operation": {"mode": "join", "body": "Body1"}}}
             ]}]}
            """
        let result = try await engine.rebuild(try CADDocument(json: Data(json.utf8)))
        let part = try #require(result.parts.first)
        #expect(part.features[0].status == .ok)
        #expect(part.features[1].status == .ok)
        guard case .failed(.kernel(let message)) = part.features[2].status else {
            Issue.record("expected a kernel failure, got \(part.features[2].status)")
            return
        }
        #expect(message.contains("cone radii must differ"))
        #expect(part.features[3].status == .ok)
        #expect(part.bodies.map(\.name) == ["Body1"])
        let body = try #require(part.bodies.first)
        let metrics = try #require(body.metrics)
        let expected = 60.0 * 40 * 10 - .pi * 25 * 10 + 2.0 / 3 * .pi * 64
        #expect(approx(metrics.volume, expected))
        #expect(metrics.isClosed)
        #expect(metrics.solidCount == 1)
        #expect((body.mesh?.triangleCount ?? 0) > 12)
        #expect(result.triangleCount == body.mesh?.triangleCount)
    }

    @Test("Body topology names faces after the features that made them")
    func topologyNames() async throws {
        let document = CADDocument(parts: [
            Part(
                name: "Plate",
                features: [
                    Feature(name: "Base", kind: .primitive(PrimitiveFeature(.box(width: 60, depth: 40, height: 10)))),
                    Feature(
                        name: "Hole",
                        kind: .primitive(
                            PrimitiveFeature(
                                .cylinder(radius: 2.75, height: 10),
                                placement: Placement(translation: Vector3(30, 20, 0)), operation: .cut("Body1")))),
                ])
        ])
        let topology = try #require(try await engine.rebuild(document).bodies.first?.topology)
        let names = Set(topology.faces.flatMap(\.names))

        #expect(
            names == ["Base.left", "Base.right", "Base.front", "Base.back", "Base.bottom", "Base.top", "Hole.side"])
        let wall = try #require(topology.faces.first { $0.names == ["Hole.side"] })
        #expect(wall.surface == .cylinder)
        #expect(approx(wall.radius, 2.75))
        #expect(topology.edges.filter { $0.curve == .circle }.count == 2)
    }

    @Test("Rotations are given in degrees")
    func degrees() async throws {
        let box = Feature(
            name: "B",
            kind: .primitive(
                PrimitiveFeature(
                    .box(width: 10, depth: 20, height: 5), placement: Placement(rotationDegrees: 90))))
        let result = try await engine.rebuild(CADDocument(parts: [Part(name: "P", features: [box])]))
        let metrics = try #require(result.bodies.first?.metrics)
        #expect(approx(metrics.boundsMin.x, -20))
        #expect(approx(metrics.boundsMax.x, 0))
        #expect(approx(metrics.boundsMax.y, 10))
        #expect(approx(metrics.boundsMax.z, 5))
    }

    @Test("Booleans, tori and transforms reach the kernel")
    func booleanAndTransform() async throws {
        let features = [
            Feature(name: "A", kind: .primitive(PrimitiveFeature(.box(width: 10, depth: 10, height: 10)))),
            Feature(
                name: "B",
                kind: .primitive(
                    PrimitiveFeature(
                        .box(width: 10, depth: 10, height: 10),
                        placement: Placement(translation: Vector3(5, 0, 0))))),
            Feature(name: "U", kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: ["Body2"]))),
            Feature(
                name: "M",
                kind: .transform(TransformFeature(body: "Body1", placement: Placement(translation: Vector3(0, 0, 100))))
            ),
            Feature(name: "T", kind: .primitive(PrimitiveFeature(.torus(majorRadius: 10, minorRadius: 2)))),
        ]
        let result = try await engine.rebuild(CADDocument(parts: [Part(name: "P", features: features)]))
        let part = try #require(result.parts.first)
        #expect(part.features.allSatisfy { $0.status == .ok })
        #expect(part.bodies.map(\.name) == ["Body1", "Body3"])
        let merged = try #require(part.bodies.first?.metrics)
        #expect(approx(merged.volume, 1500))
        #expect(approx(merged.boundsMin.z, 100))
        let expectedVolume: Double = 2 * .pi * .pi * 10 * 4
        #expect(approx(part.bodies[1].metrics?.volume, expectedVolume))
    }

    @Test("Distances and interference are measured on the rebuilt bodies")
    func measure() async throws {
        let json = """
            {"format": 1, "units": "mm", "parameters": [],
             "parts": [{"name": "P", "features": [
               {"name": "Plate", "kind": {"type": "box", "width": 60, "depth": 40, "height": 10}},
               {"name": "Hole", "kind": {"type": "cylinder", "radius": 2.75, "height": 10,
                 "placement": {"translation": {"x": 30, "y": 20}}, "operation": {"mode": "cut", "body": "Body1"}}},
               {"name": "A", "kind": {"type": "box", "width": 10, "depth": 10, "height": 10,
                 "placement": {"translation": {"x": 100}}}},
               {"name": "B", "kind": {"type": "box", "width": 10, "depth": 10, "height": 10,
                 "placement": {"translation": {"x": 105}}}},
               {"name": "C", "kind": {"type": "box", "width": 10, "depth": 10, "height": 10,
                 "placement": {"translation": {"x": 200}}}}
             ]}]}
            """
        let model = try await engine.build(try CADDocument(json: Data(json.utf8)))
        let part = model.result.parts[0].id
        let key = { (name: String) in BodyKey(part: part, body: name) }
        let topology = try #require(model.result.bodies.first?.topology)
        let hole = try #require(topology.faces.firstIndex { $0.names.contains("Hole.side") })
        let left = try #require(topology.faces.firstIndex { $0.names.contains("Plate.left") })

        let gap = try model.geometry.distance(.face(key("Body1"), hole), .face(key("Body1"), left))

        #expect(approx(gap.distance, 30 - 2.75))
        #expect(approx(try model.geometry.interference(key("Body2"), key("Body3")), 500))
        #expect(try model.geometry.interference(key("Body2"), key("Body4")) == 0)
        #expect(approx(try model.geometry.distance(.body(key("Body3")), .body(key("Body4"))).distance, 85))
        #expect(approx(try model.geometry.distance(.point(SIMD3(10, 10, 30)), .body(key("Body1"))).distance, 20))
    }
}
