import Foundation
import Testing
import simd

@testable import CADModel

private func boxFeature(_ name: String, _ w: Double, _ d: Double, _ h: Double) -> Feature {
    Feature(
        name: name, kind: .primitive(PrimitiveFeature(.box(width: .number(w), depth: .number(d), height: .number(h)))))
}

private func sketchFeature(
    _ name: String = "Sketch1", plane: SketchPlane = .base(.xy), _ sketch: SketchFeature = rectangleSketch
)
    -> Feature
{
    var sketch = sketch
    sketch.plane = plane
    return Feature(name: name, kind: .sketch(sketch))
}

private func extrudeFeature(
    _ name: String = "Extrude1", sketch: String = "Sketch1", _ extent: ExtrudeExtent, reversed: Bool = false,
    operation: SolidOperation = .newBody
) -> Feature {
    Feature(
        name: name,
        kind: .extrude(ExtrudeFeature(sketch: sketch, extent: extent, reversed: reversed, operation: operation)))
}

private func extrudeFeature(
    sketch: String = "Sketch1", _ extent: ExtrudeExtent, reversed: Bool = false, operation: SolidOperation = .newBody
) -> Feature {
    extrudeFeature("Extrude1", sketch: sketch, extent, reversed: reversed, operation: operation)
}

private let circleSketch = SketchFeature(
    plane: .base(.xy), entities: [SketchEntity(name: "circle1", .circle(center: SketchPoint2(5, 5), radius: 2))])

@Suite("Rebuilding sketches")
struct SketchRebuildTests {
    let kernel = FakeKernel()

    private func rebuild(_ features: [Feature], solver: (any SketchSolving)? = FakeSketchSolver()) async throws
        -> PartResult
    {
        let engine = RebuildEngine(kernel: kernel, sketchSolver: solver)
        let document = CADDocument(
            parameters: [Parameter(name: "width", expression: 60)], parts: [Part(name: "P", features: features)])
        return try #require(try await engine.rebuild(document).parts.first)
    }

    private var extrudeCalls: [String] { kernel.calls.filter { $0.hasPrefix("extrude") || $0.hasPrefix("revolve") } }

    @Test("An extrude sends the sketch's region with qualified curve names to the kernel")
    func extrudeCallsKernel() async throws {
        let part = try await rebuild([sketchFeature(), extrudeFeature(.distance(10))])
        #expect(part.features.map(\.status) == [.ok, .ok])
        #expect(part.features[1].body == "Body1")
        #expect(part.bodies.map(\.name) == ["Body1"])
        #expect(
            extrudeCalls == [
                "extrude 1 regions 0...10 as Extrude1: Sketch1.line1, Sketch1.line2, Sketch1.line3, Sketch1.line4"
            ])
    }

    @Test("Reversed extrudes go below the plane; symmetric ones straddle it")
    func reversedSymmetric() async throws {
        _ = try await rebuild([
            sketchFeature(), extrudeFeature("A", .distance(10), reversed: true), extrudeFeature("B", .symmetric(10)),
        ])
        #expect(
            extrudeCalls.map { $0.components(separatedBy: " as ")[0] } == [
                "extrude 1 regions 0...-10", "extrude 1 regions -5...5",
            ])
    }

    @Test("Through all spans the target body along the normal with a margin")
    func throughAll() async throws {
        let part = try await rebuild([
            boxFeature("Box1", 10, 10, 6), sketchFeature(plane: .base(.xy, offset: 6), circleSketch),
            extrudeFeature("Cut1", .throughAll, operation: .cut("Body1")),
            extrudeFeature("Bad", .throughAll),
        ])
        #expect(part.features.map(\.status).prefix(3) == [.ok, .ok, .ok])
        #expect(extrudeCalls.first?.hasPrefix("extrude 1 regions -7...1 as Cut1") == true)
        #expect(part.features[3].status == .failed(.extent("through all needs join, cut or intersect with a body")))
    }

    @Test("Up to a face goes to a parallel planar face and refuses others")
    func upToFace() async throws {
        let part = try await rebuild([
            boxFeature("Box1", 10, 10, 6), sketchFeature(),
            extrudeFeature("Up", .upToFace(body: "Body1", face: .name("Box1.top"))),
            extrudeFeature("Tilted", .upToFace(body: "Body1", face: .name("Box1.front"))),
        ])
        #expect(extrudeCalls.first?.hasPrefix("extrude 1 regions 0...6 as Up") == true)
        guard case .failed(.extent(let message)) = part.features[3].status else {
            Issue.record("expected an extent failure, got \(part.features[3].status)")
            return
        }
        #expect(message.contains("parallel"))
    }

    @Test("A sketch on a face takes the face's plane, origin projected, axes from the world")
    func faceFrame() async throws {
        let part = try await rebuild([
            boxFeature("Box1", 10, 10, 6),
            sketchFeature("OnTop", plane: .face(body: "Body1", face: .name("Box1.top"), offset: 2), circleSketch),
            sketchFeature("OnRight", plane: .face(body: "Body1", face: .name("Box1.right")), circleSketch),
        ])
        #expect(part.features.map(\.status) == [.ok, .ok, .ok])
        let top = try #require(part.sketches.first { $0.name == "OnTop" }).frame
        #expect(top.origin == SIMD3(0, 0, 8))
        #expect(top.xAxis == SIMD3(1, 0, 0))
        #expect(top.yAxis == SIMD3(0, 1, 0))
        let right = try #require(part.sketches.first { $0.name == "OnRight" }).frame
        #expect(right.origin == SIMD3(10, 0, 0))
        #expect(right.xAxis == SIMD3(0, 1, 0))
        #expect(right.yAxis == SIMD3(0, 0, 1))
    }

    @Test("Base planes: XZ has its normal along -Y")
    func baseFrames() {
        let xz = SketchFrame.base(.xz, offset: 3)
        #expect(xz.normal == SIMD3(0, -1, 0))
        #expect(xz.origin == SIMD3(0, -3, 0))
        #expect(SketchFrame.base(.yz, offset: 0).normal == SIMD3(1, 0, 0))
        #expect(xz.point(SIMD2(2, 5)) == SIMD3(2, -3, 5))
    }

    @Test("An over-constrained sketch fails, its extrude is skipped and later features still build")
    func overConstrainedSkipsExtrude() async throws {
        let part = try await rebuild(
            [sketchFeature(), extrudeFeature(.distance(10)), boxFeature("Box1", 1, 1, 1)],
            solver: FakeSketchSolver(state: .overConstrained(conflicting: [1])))
        #expect(part.features[0].status == .failed(.sketch("over-constrained, c2 conflict")))
        #expect(part.features[1].status == .skipped(dependsOn: "Sketch1"))
        #expect(part.features[2].status == .ok)
        #expect(part.sketches.first?.state == .overConstrained(conflicting: ["c2"]))
    }

    @Test("Without a solver, sketches fail and say why")
    func noSolver() async throws {
        let part = try await rebuild([sketchFeature()], solver: nil)
        #expect(part.features[0].status == .failed(.sketch("no sketch solver is available")))
    }

    @Test("An extrude of an unknown sketch fails naming it")
    func unknownSketch() async throws {
        let part = try await rebuild([extrudeFeature(sketch: "Nope", .distance(1))])
        #expect(part.features[0].status == .failed(.sketch("no sketch named 'Nope' comes before this feature")))
    }

    @Test("Revolve axes: a sketch line, a world axis and a body edge")
    func revolveAxes() async throws {
        var section = SketchFeature(
            plane: .base(.xz),
            entities: [
                SketchEntity(name: "line1", .line(start: SketchPoint2(20, 0), end: SketchPoint2(30, 0))),
                SketchEntity(name: "line2", .line(start: SketchPoint2(30, 0), end: SketchPoint2(30, 10))),
                SketchEntity(name: "line3", .line(start: SketchPoint2(30, 10), end: SketchPoint2(20, 10))),
                SketchEntity(name: "line4", .line(start: SketchPoint2(20, 10), end: SketchPoint2(20, 0))),
                SketchEntity(
                    name: "line5", .line(start: SketchPoint2(0, 0), end: SketchPoint2(0, 10)), construction: true),
            ])
        section.constraints = []
        func revolve(_ name: String, _ axis: RevolveAxis) -> Feature {
            Feature(name: name, kind: .revolve(RevolveFeature(sketch: "Sketch1", axis: axis, angle: 90)))
        }
        let part = try await rebuild([
            boxFeature("Box1", 10, 10, 6), sketchFeature(plane: .base(.xz), section),
            revolve("A", .sketchLine("line5")),
            revolve("B", .z), revolve("C", .edge(body: "Body1", edge: .name("edge(Box1.front, Box1.left)"))),
            revolve("D", .sketchLine("line9")),
        ])
        #expect(part.features.map(\.status).prefix(5) == [.ok, .ok, .ok, .ok, .ok])
        #expect(
            extrudeCalls == [
                "revolve 1 regions about (0,0,0) along (0,0,1) by 90 as A",
                "revolve 1 regions about (0,0,0) along (0,0,1) by 90 as B",
                "revolve 1 regions about (0,0,0) along (0,0,1) by 90 as C",
            ])
        #expect(part.features[5].status == .failed(.sketch("the axis line9 is not a line of Sketch1")))
    }

    @Test("Sketch results carry the solved entities, the state and the profiles")
    func sketchResultsReported() async throws {
        let part = try await rebuild(
            [sketchFeature()], solver: FakeSketchSolver(state: .underConstrained(dof: 2), degreesOfFreedom: 2))
        let result = try #require(part.sketches.first)
        #expect(result.name == "Sketch1")
        #expect(result.entities == rectangleSketch.entities)
        #expect(result.state == .underConstrained(dof: 2))
        #expect(result.degreesOfFreedom == 2)
        #expect(result.profiles.loops.count == 1)
    }
}
