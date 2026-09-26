import CADModel
import CADModelKernel
import CADModelSolvers
import Foundation
import simd
import Testing

@Suite("Motion integration")
struct MotionIntegrationTests {
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

    /// A lid hinged on the box's back top edge (y 40, z 30); positive angles open it.
    private func hingedLid(value: Scalar?, start: Placement = .identity) -> CADDocument {
        let box = Part(name: "Box", features: [Self.box("Box", 60, 40, 30)])
        let lid = Part(name: "Lid", features: [Self.box("Lid", 60, 40, 5)])
        let base = Instance(name: "Base", part: box.id, grounded: true)
        let top = Instance(name: "Lid", part: lid.id, placement: start)
        let hinge = Joint(
            name: "Hinge", kind: .revolute,
            a: JointFrameRef(instance: base.id, face: .name("Box.left"), offset: JointOffset(x: 20, y: -15)),
            b: JointFrameRef(instance: top.id, face: .name("Lid.left"), offset: JointOffset(x: 20, y: 2.5)),
            flip: true, limits: JointLimits(min: 0, max: 110), value: value
        )
        return CADDocument(parts: [box, lid], assembly: Assembly(instances: [base, top], joints: [hinge]))
    }

    @Test("A hinge driven to 0° keeps the lid closed and leaves it no freedom")
    func hingeClosedAt0() async throws {
        let result = try await rebuild(hingedLid(value: 0))
        let (low, high) = try bounds(result.assembly?.instance(named: "Lid"))

        #expect(result.assembly?.joints.first?.status == .ok)
        #expect(result.assembly?.joints.first?.value == 0)
        #expect(result.assembly?.instance(named: "Lid")?.freedoms == 0)
        #expect(close(low, SIMD3(0, 0, 30)))
        #expect(close(high, SIMD3(60, 40, 35)))
    }

    @Test("A hinge driven to 90° stands the lid upright behind the box")
    func hingeAt90() async throws {
        let result = try await rebuild(hingedLid(value: 90))
        let (low, high) = try bounds(result.assembly?.instance(named: "Lid"))

        #expect(result.assembly?.joints.first?.status == .ok)
        #expect(close(low, SIMD3(0, 40, 30)))
        #expect(close(high, SIMD3(60, 45, 70)))
    }

    @Test("The driven pose does not depend on where the lid starts")
    func hingeAt90FromRotatedStart() async throws {
        let start = Placement(translation: Vector3(-80, 30, 120), rotationAxis: Vector3(0, 1, 0), rotationDegrees: 150)
        let result = try await rebuild(hingedLid(value: 90, start: start))
        let (low, high) = try bounds(result.assembly?.instance(named: "Lid"))

        #expect(result.assembly?.joints.first?.status == .ok)
        #expect(close(low, SIMD3(0, 40, 30)))
        #expect(close(high, SIMD3(60, 45, 70)))
    }

    @Test("A free hinge leaves the lid one freedom and reports where it rests")
    func freeHingeHasOneFreedom() async throws {
        let result = try await rebuild(hingedLid(value: nil))
        let hinge = try #require(result.assembly?.joints.first)

        #expect(hinge.status == .ok)
        let value = try #require(hinge.value)
        #expect((0...110).contains(value), "\(value)")
        #expect(!hinge.driven)
        #expect(hinge.freedoms == 1)
        #expect(result.assembly?.instance(named: "Lid")?.freedoms == 1)
        #expect(result.assembly?.instance(named: "Base")?.freedoms == 0)
    }

    @Test("A slider driven to its end stop puts the carriage at the rail's far end")
    func sliderAtTravel() async throws {
        let rail = Part(name: "Rail", features: [Self.box("Rail", 200, 20, 10)])
        let carriage = Part(name: "Carriage", features: [Self.box("Carriage", 30, 20, 15)])
        let track = Instance(name: "Track", part: rail.id, grounded: true)
        let slide = Instance(name: "Slide", part: carriage.id)
        let guide = Joint(
            name: "Guide", kind: .slider,
            a: JointFrameRef(instance: track.id, face: .name("Rail.right"), offset: JointOffset(y: 12.5, z: -200)),
            b: JointFrameRef(instance: slide.id, face: .name("Carriage.left")),
            limits: JointLimits(min: 0, max: 170), value: 170
        )
        let document = CADDocument(
            parts: [rail, carriage], assembly: Assembly(instances: [track, slide], joints: [guide])
        )
        let result = try await rebuild(document)
        let (low, high) = try bounds(result.assembly?.instance(named: "Slide"))

        #expect(result.assembly?.joints.first?.status == .ok)
        #expect(close(low, SIMD3(170, 0, 10)))
        #expect(close(high, SIMD3(200, 20, 25)))
    }
}
