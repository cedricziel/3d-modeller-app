import CADModel
import CADModelKernel
import CADModelSolvers
import Foundation
import Testing
import simd

@Suite("Assembly integration")
struct AssemblyIntegrationTests {
    private static func box(_ name: String, _ w: Scalar, _ d: Scalar, _ h: Scalar) -> Feature {
        Feature(name: name, kind: .primitive(PrimitiveFeature(.box(width: w, depth: d, height: h))))
    }

    private func rebuild(_ document: CADDocument) async throws -> RebuildResult {
        try await RebuildEngine(kernel: OCCTGeometryKernel(), assemblySolver: OndselAssemblySolver()).rebuild(document)
    }

    private func bounds(_ instance: InstanceResult?) throws -> (SIMD3<Double>, SIMD3<Double>) {
        let metrics = try #require(instance?.bodies.first?.metrics)
        return (metrics.boundsMin, metrics.boundsMax)
    }

    private func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ tolerance: Double = 1e-4) -> Bool {
        simd_distance(a, b) <= tolerance
    }

    private func lidOnBox(start: Placement) -> CADDocument {
        let box = Part(name: "Box", features: [Self.box("Box1", 60, 40, 30)])
        let lid = Part(name: "Lid", features: [Self.box("Lid1", 60, 40, 5)])
        let base = Instance(name: "Base", part: box.id, grounded: true)
        let top = Instance(name: "Top", part: lid.id, placement: start)
        let joint = Joint(
            name: "Mate", kind: .fixed, a: JointFrameRef(instance: base.id, face: .name("Box1.top")),
            b: JointFrameRef(instance: top.id, face: .name("Lid1.bottom")))
        return CADDocument(parts: [box, lid], assembly: Assembly(instances: [base, top], joints: [joint]))
    }

    @Test("A fixed joint puts the lid flush on the box")
    func lidOnBoxFixed() async throws {
        let result = try await rebuild(lidOnBox(start: .identity))
        let (low, high) = try bounds(result.assembly?.instance(named: "Top"))

        #expect(result.assembly?.joints.first?.status == .ok)
        #expect(close(low, SIMD3(0, 0, 30)))
        #expect(close(high, SIMD3(60, 40, 35)))
    }

    @Test("A lid that starts upside down and far away still lands flush")
    func upsideDownLidStillMates() async throws {
        let start = Placement(
            translation: Vector3(100, -50, 80), rotationAxis: Vector3(1, 0, 0), rotationDegrees: 180)
        let result = try await rebuild(lidOnBox(start: start))
        let (low, high) = try bounds(result.assembly?.instance(named: "Top"))

        #expect(result.assembly?.joints.first?.status == .ok)
        #expect(close(low, SIMD3(0, 0, 30)))
        #expect(close(high, SIMD3(60, 40, 35)))
    }

    @Test("A revolute joint on circular edges puts the pin in the hole, flush at the bottom")
    func pinInHole() async throws {
        let plate = Part(
            name: "Plate",
            features: [
                Self.box("Plate", 40, 40, 10),
                Feature(
                    name: "Hole",
                    kind: .primitive(
                        PrimitiveFeature(
                            .cylinder(radius: 5.5, height: 12), placement: Placement(translation: Vector3(20, 20, -1)),
                            operation: .cut("Body1")))),
            ])
        let pin = Part(
            name: "Pin",
            features: [Feature(name: "Pin", kind: .primitive(PrimitiveFeature(.cylinder(radius: 5, height: 30))))])
        let base = Instance(name: "Base", part: plate.id, grounded: true)
        let peg = Instance(name: "Peg", part: pin.id, placement: Placement(translation: Vector3(3, 4, 50)))
        let joint = Joint(
            name: "Hinge", kind: .revolute,
            a: JointFrameRef(instance: base.id, face: .name("Hole.side"), edge: .name("edge(Hole.side, Plate.bottom)")),
            b: JointFrameRef(instance: peg.id, face: .name("Pin.side"), edge: .name("edge(Pin.side, Pin.bottom)")),
            flip: true)
        let document = CADDocument(parts: [plate, pin], assembly: Assembly(instances: [base, peg], joints: [joint]))
        let result = try await rebuild(document)
        let (low, high) = try bounds(result.assembly?.instance(named: "Peg"))

        #expect(result.assembly?.joints.first?.status == .ok)
        #expect(close(low, SIMD3(15, 15, 0)))
        #expect(close(high, SIMD3(25, 25, 30)))
    }

    @Test("A slider keeps the carriage on the rail at its starting distance")
    func sliderOnRail() async throws {
        let rail = Part(name: "Rail", features: [Self.box("Rail", 200, 20, 10)])
        let carriage = Part(name: "Carriage", features: [Self.box("Carriage", 30, 20, 15)])
        let base = Instance(name: "Track", part: rail.id, grounded: true)
        let slide = Instance(
            name: "Slide", part: carriage.id, placement: Placement(translation: Vector3(50, 3, 12)))
        let joint = Joint(
            name: "Guide", kind: .slider,
            a: JointFrameRef(instance: base.id, face: .name("Rail.left"), offset: JointOffset(y: -12.5)),
            b: JointFrameRef(instance: slide.id, face: .name("Carriage.left")), flip: true)
        let document = CADDocument(
            parts: [rail, carriage], assembly: Assembly(instances: [base, slide], joints: [joint]))
        let result = try await rebuild(document)
        let status = try #require(result.assembly?.joints.first?.status)
        let (low, high) = try bounds(result.assembly?.instance(named: "Slide"))

        #expect(status == .ok)
        #expect(close(low, SIMD3(50, 0, 10)))
        #expect(close(high, SIMD3(80, 20, 25)))
    }
}
