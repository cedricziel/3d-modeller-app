import CADModel
import CADModelKernel
import CADModelSolvers
import Foundation
import Testing

/// Constraint names are handed out in order.
struct SketchBuilder {
    var entities: [SketchEntity] = []
    var constraints: [SketchConstraint] = []

    mutating func add(_ entity: SketchEntity) { entities.append(entity) }

    mutating func constrain(
        _ kind: SketchConstraintKind, entities: [String] = [], points: [String] = [], value: Scalar? = nil,
        at: [Scalar]? = nil
    ) {
        constraints.append(
            SketchConstraint(
                name: "c\(constraints.count + 1)", kind, entities: entities, points: points, value: value, at: at))
    }

    /// A closed rectangle of lines `line<first>…line<first+3>`, axis-aligned, dimensioned `width` × `height`.
    mutating func rectangle(
        first: Int, x: Double, y: Double, width: Scalar, height: Scalar, guess: (Double, Double)
    ) {
        let (w, h) = guess
        let corners = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
        let names = (first..<first + 4).map { "line\($0)" }
        for index in 0..<4 {
            let (a, b) = (corners[index], corners[(index + 1) % 4])
            add(SketchEntity(name: names[index], .line(start: SketchPoint2(a.0, a.1), end: SketchPoint2(b.0, b.1))))
        }
        for index in 0..<4 {
            constrain(.coincident, points: ["\(names[index]).end", "\(names[(index + 1) % 4]).start"])
        }
        constrain(.horizontal, entities: [names[0]])
        constrain(.horizontal, entities: [names[2]])
        constrain(.vertical, entities: [names[1]])
        constrain(.vertical, entities: [names[3]])
        constrain(.distance, points: ["\(names[0]).start", "\(names[0]).end"], value: width)
        constrain(.distance, points: ["\(names[1]).start", "\(names[1]).end"], value: height)
    }

    func feature(_ plane: SketchPlane = .base(.xy)) -> FeatureKind {
        .sketch(SketchFeature(plane: plane, entities: entities, constraints: constraints))
    }
}

@Suite("Sketches with PlaneGCS and OCCT")
struct SketchIntegrationTests {
    let engine = RebuildEngine(kernel: OCCTGeometryKernel(), sketchSolver: PlaneGCSSketchSolver())

    static let parameters = [
        Parameter(name: "width", expression: 60), Parameter(name: "depth", expression: 40),
        Parameter(name: "t", expression: 6), Parameter(name: "hole_d", expression: 5.5),
    ]

    /// A fully constrained plate outline with a centred hole, sloppily drawn.
    static var plateSketch: SketchBuilder {
        var sketch = SketchBuilder()
        sketch.rectangle(first: 1, x: 0, y: 0, width: "width", height: "depth", guess: (57, 42))
        sketch.constrain(.fixed, points: ["line1.start"], at: [0, 0])
        sketch.add(SketchEntity(name: "circle1", .circle(center: SketchPoint2(28, 21), radius: 3)))
        sketch.constrain(.diameter, entities: ["circle1"], value: "hole_d")
        sketch.constrain(.pointLineDistance, entities: ["line1"], points: ["circle1.center"], value: "depth / 2")
        sketch.constrain(.pointLineDistance, entities: ["line4"], points: ["circle1.center"], value: "width / 2")
        return sketch
    }

    private func rebuild(_ kinds: [(String, FeatureKind)], parameters: [Parameter] = parameters) async throws
        -> PartResult
    {
        let part = Part(name: "Plate", features: kinds.map { Feature(name: $0.0, kind: $0.1) })
        return try #require(try await engine.rebuild(CADDocument(parameters: parameters, parts: [part])).parts.first)
    }

    private func volume(_ part: PartResult, _ body: String = "Body1") throws -> Double {
        try #require(part.bodies.first { $0.name == body }?.metrics?.volume)
    }

    private func faceNames(_ part: PartResult) -> Set<String> {
        Set(part.bodies.first?.topology?.faces.flatMap(\.names) ?? [])
    }

    @Test("A fully constrained plate sketch extrudes into a plate with a named hole, and fillets by filter")
    func plateFromSketch() async throws {
        let part = try await rebuild([
            ("Sketch1", Self.plateSketch.feature()),
            ("Extrude1", .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance("t")))),
            ("Round", .fillet(FilletFeature(body: "Body1", edges: [.filter("parallel Z and farthest +X")], radius: 3))),
        ])
        #expect(part.features.map(\.status) == [.ok, .ok, .ok])
        #expect(part.sketches.first?.state == .fullyConstrained)
        let expected: Double = 60 * 40 * 6 - Double.pi * 2.75 * 2.75 * 6 - 2 * 9 * (1 - Double.pi / 4) * 6
        #expect(abs(try volume(part) - expected) < 1e-3)
        #expect(faceNames(part).isSuperset(of: ["Extrude1.side[Sketch1.circle1]", "Extrude1.start", "Extrude1.end"]))
    }

    @Test("Changing a parameter a sketch dimension uses changes the solid")
    func parameterChangeResolves() async throws {
        var parameters = Self.parameters
        parameters[0] = Parameter(name: "width", expression: 80)
        let part = try await rebuild(
            [
                ("Sketch1", Self.plateSketch.feature()),
                ("Extrude1", .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance("t")))),
            ], parameters: parameters)
        let expected: Double = 80 * 40 * 6 - Double.pi * 2.75 * 2.75 * 6
        #expect(abs(try volume(part) - expected) < 1e-3)
    }

    @Test("A cup section revolves about a construction line")
    func revolveCup() async throws {
        var sketch = SketchBuilder()
        let points: [(Double, Double)] = [(0, 0), (30, 0), (30, 50), (27, 50), (27, 4), (0, 4)]
        for index in points.indices {
            let (a, b) = (points[index], points[(index + 1) % points.count])
            sketch.add(
                SketchEntity(
                    name: "line\(index + 1)", .line(start: SketchPoint2(a.0, a.1), end: SketchPoint2(b.0, b.1))))
        }
        sketch.add(
            SketchEntity(name: "axis", .line(start: SketchPoint2(0, 0), end: SketchPoint2(0, 10)), construction: true))
        let part = try await rebuild([
            ("Section", sketch.feature(.base(.xz))),
            ("Cup", .revolve(RevolveFeature(sketch: "Section", axis: .sketchLine("axis")))),
        ])
        #expect(part.features.map(\.status) == [.ok, .ok])
        let expected: Double = Double.pi * (900 * 50 - 729 * 46)
        #expect(abs(try volume(part) - expected) < 1e-2)
        #expect(faceNames(part).contains("Cup.side[Section.line2]"))
    }

    @Test("A circle sketched on the top face cuts a through hole")
    func throughAllCutFromTopFace() async throws {
        var sketch = SketchBuilder()
        sketch.add(SketchEntity(name: "circle1", .circle(center: SketchPoint2(30, 20), radius: 2.75)))
        let part = try await rebuild([
            ("Box1", .primitive(PrimitiveFeature(.box(width: 60, depth: 40, height: 6)))),
            ("Sketch1", sketch.feature(.face(body: "Body1", face: .name("Box1.top")))),
            ("Cut1", .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .throughAll, operation: .cut("Body1")))),
        ])
        #expect(part.features.map(\.status) == [.ok, .ok, .ok])
        let expected: Double = 60 * 40 * 6 - Double.pi * 2.75 * 2.75 * 6
        #expect(abs(try volume(part) - expected) < 1e-3)
        #expect(faceNames(part).contains("Cut1.side[Sketch1.circle1]"))
    }

    @Test("An open profile fails the extrude and names the free ends")
    func extrudeOpenProfileFails() async throws {
        var sketch = SketchBuilder()
        sketch.add(SketchEntity(name: "line1", .line(start: SketchPoint2(0, 0), end: SketchPoint2(10, 0))))
        sketch.add(SketchEntity(name: "line2", .line(start: SketchPoint2(10, 0), end: SketchPoint2(10, 10))))
        let part = try await rebuild([
            ("Sketch1", sketch.feature()),
            ("Extrude1", .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance(1)))),
        ])
        #expect(part.features[0].status == .ok)
        #expect(part.features[1].status.description.contains("open ends: line1.start (0, 0), line2.end (10, 10)"))
    }

    @Test("A second width conflicts, and the conflict names the constraints")
    func conflictingConstraintsNamed() async throws {
        var sketch = Self.plateSketch
        sketch.constrain(.distance, points: ["line3.start", "line3.end"], value: 50)
        let part = try await rebuild([
            ("Sketch1", sketch.feature()),
            ("Extrude1", .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance(1)))),
        ])
        let status = part.features[0].status.description
        #expect(status.hasPrefix("failed: over-constrained"))
        #expect(status.contains("c15"), "\(status)")
        #expect(part.features[1].status == .skipped(dependsOn: "Sketch1"))
    }

    @Test("A slot joined with tangentAt solves and extrudes")
    func tangentAtArcSlot() async throws {
        var sketch = SketchBuilder()
        sketch.add(SketchEntity(name: "line1", .line(start: SketchPoint2(0, -4), end: SketchPoint2(19, -4.5))))
        sketch.add(
            SketchEntity(name: "arc1", .arc(center: SketchPoint2(20, 0), radius: 4, startAngle: -90, endAngle: 90)))
        sketch.add(SketchEntity(name: "line2", .line(start: SketchPoint2(20, 4), end: SketchPoint2(0, 4))))
        sketch.add(
            SketchEntity(name: "arc2", .arc(center: SketchPoint2(0, 0), radius: 4, startAngle: 90, endAngle: 270)))
        sketch.constrain(.tangentAt, points: ["line1.end", "arc1.start"])
        sketch.constrain(.tangentAt, points: ["arc1.end", "line2.start"])
        sketch.constrain(.tangentAt, points: ["line2.end", "arc2.start"])
        sketch.constrain(.tangentAt, points: ["arc2.end", "line1.start"])
        sketch.constrain(.horizontal, entities: ["line1"])
        sketch.constrain(.fixed, points: ["arc2.center"], at: [0, 0])
        sketch.constrain(.distance, points: ["arc2.center", "arc1.center"], value: 20)
        sketch.constrain(.radius, entities: ["arc1"], value: 4)
        sketch.constrain(.equal, entities: ["arc1", "arc2"])
        let part = try await rebuild([
            ("Sketch1", sketch.feature()),
            ("Extrude1", .extrude(ExtrudeFeature(sketch: "Sketch1", extent: .distance(3)))),
        ])
        #expect(part.features.map(\.status) == [.ok, .ok])
        #expect(part.sketches.first?.state.isUsable == true)
        let expected: Double = (20 * 8 + Double.pi * 16) * 3
        #expect(abs(try volume(part) - expected) < 1e-3)
    }

    @Test("A 30-entity sketch solves quickly even in a debug build")
    func debugTiming() async throws {
        var sketch = SketchBuilder()
        for index in 0..<7 {
            sketch.rectangle(
                first: index * 4 + 1, x: Double(index) * 12, y: 0, width: 10, height: 10, guess: (9.5, 10.5))
            sketch.constrain(.fixed, points: ["line\(index * 4 + 1).start"], at: [.number(Double(index) * 12), 0])
        }
        sketch.add(SketchEntity(name: "circle1", .circle(center: SketchPoint2(5, 5), radius: 2)))
        sketch.add(SketchEntity(name: "circle2", .circle(center: SketchPoint2(17, 5), radius: 2)))
        sketch.constrain(.radius, entities: ["circle1"], value: 2)
        sketch.constrain(.equal, entities: ["circle1", "circle2"])
        let clock = ContinuousClock()
        let start = clock.now
        let part = try await rebuild([("Sketch1", sketch.feature())])
        let elapsed = clock.now - start
        print("30-entity sketch rebuild took \(elapsed)")
        #expect(part.features[0].status == .ok)
        #expect(elapsed < .seconds(2))
    }
}
