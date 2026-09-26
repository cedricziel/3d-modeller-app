@testable import CADModel
import Foundation
import simd
import Testing

@Suite("Joint drive")
struct JointDriveTests {
    private let part = Part(
        name: "Block",
        features: [Feature(name: "Box", kind: .primitive(PrimitiveFeature(.box(width: 10, depth: 20, height: 30))))]
    )

    private func document(
        _ kind: JointKind, value: Scalar? = nil, limits: JointLimits? = nil, parameters: [Parameter] = []
    ) -> CADDocument {
        let base = Instance(name: "Base", part: part.id, grounded: true)
        let top = Instance(name: "Top", part: part.id)
        let joint = Joint(
            name: "Hinge", kind: kind, a: JointFrameRef(instance: base.id, face: .name("Box.top")),
            b: JointFrameRef(instance: top.id, face: .name("Box.bottom")), limits: limits, value: value
        )
        return CADDocument(
            parameters: parameters, parts: [part], assembly: Assembly(instances: [base, top], joints: [joint])
        )
    }

    private func rebuild(_ document: CADDocument, _ solver: FakeAssemblySolver) async throws -> RebuildResult {
        try await RebuildEngine(kernel: FakeKernel(), assemblySolver: solver).rebuild(document)
    }

    private func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool {
        simd_distance(a, b) < 1e-9
    }

    @Test("A driven revolute reaches the solver as a fixed joint with side a turned by the value")
    func revoluteDrivenBecomesFixed() async throws {
        let solver = FakeAssemblySolver()
        let result = try await rebuild(document(.revolute, value: 30), solver)
        let joint = try #require(solver.received.first?.joints.first)
        let expectedX = SIMD3<Double>(cos(.pi / 6), sin(.pi / 6), 0)
        let hinge = try #require(result.assembly?.joints.first)

        #expect(joint.kind == .fixed)
        #expect(close(joint.markerA.rotation.columns.0, expectedX))
        #expect(close(joint.markerA.translation, SIMD3(5, 10, 30)))
        #expect(hinge.status == .ok)
        #expect(hinge.value == 30)
        #expect(hinge.driven)
        #expect(hinge.freedoms == 0)
    }

    @Test("A driven slider reaches the solver as a fixed joint with side a moved along its z axis")
    func sliderDrivenBecomesFixed() async throws {
        let solver = FakeAssemblySolver()
        _ = try await rebuild(document(.slider, value: 12), solver)
        let joint = try #require(solver.received.first?.joints.first)

        #expect(joint.kind == .fixed)
        #expect(close(joint.markerA.translation, SIMD3(5, 10, 42)))
    }

    @Test("A driven cylindrical joint reaches the solver as a revolute moved along z; its turn stays free")
    func cylindricalDrivenBecomesRevolute() async throws {
        let solver = FakeAssemblySolver()
        let result = try await rebuild(document(.cylindrical, value: -4), solver)
        let joint = try #require(solver.received.first?.joints.first)

        #expect(joint.kind == .revolute)
        #expect(close(joint.markerA.translation, SIMD3(5, 10, 26)))
        #expect(result.assembly?.joints.first?.freedoms == 1)
    }

    @Test("A free revolute reports the angle the solver left it at")
    func freeJointMeasured() async throws {
        let turn = simd_double3x3(simd_quatd(angle: 40 * .pi / 180, axis: SIMD3(0, 0, 1)))
        let pivot = SIMD3<Double>(5, 10, 30)
        let turned = RigidTransform(rotation: turn, translation: pivot - turn * SIMD3(5, 10, 0))
        let solver = FakeAssemblySolver { assembly in
            var solution = FakeAssemblySolver.unchanged(assembly)
            solution.placements[assembly.joints[0].bodyB] = turned
            return solution
        }
        let result = try await rebuild(document(.revolute, limits: JointLimits(min: 0, max: 90)), solver)
        let hinge = try #require(result.assembly?.joints.first)
        let value = try #require(hinge.value)

        #expect(solver.received.first?.joints.first?.kind == .revolute)
        #expect(abs(value - 40) < 1e-9)
        #expect(!hinge.driven)
        #expect(hinge.freedoms == 1)
        #expect(hinge.minimum == 0)
        #expect(hinge.maximum == 90)
    }

    @Test("A value on a ball joint fails it; the joint is solved as a plain ball")
    func valueOnBallFails() async throws {
        let solver = FakeAssemblySolver()
        let result = try await rebuild(document(.ball, value: 10), solver)

        #expect(solver.received.first?.joints.first?.kind == .ball)
        #expect(
            result.assembly?.joints.first?.status
                == .failed("a ball joint has no single motion to drive; remove its value")
        )
    }

    @Test("Limits on a fixed joint fail it")
    func limitsOnFixedFail() async throws {
        let result = try await rebuild(document(.fixed, limits: JointLimits(max: 5)), FakeAssemblySolver())
        #expect(
            result.assembly?.joints.first?.status
                == .failed("a fixed joint has no single motion to limit; remove its limits")
        )
    }

    @Test("A value outside the limits fails the joint, which is solved undriven")
    func valueOutsideLimitsFails() async throws {
        let solver = FakeAssemblySolver()
        let result = try await rebuild(
            document(.revolute, value: 120, limits: JointLimits(min: 0, max: 110)), solver
        )

        #expect(solver.received.first?.joints.first?.kind == .revolute)
        #expect(result.assembly?.joints.first?.status == .failed("value 120° is outside its limits 0°…110°"))
        #expect(result.assembly?.joints.first?.driven == false)
    }

    @Test("Limits follow parameters")
    func limitsFromParameters() async throws {
        let limits = JointLimits(min: 0, max: "open")
        let narrow = try await rebuild(
            document(.slider, value: 90, limits: limits, parameters: [Parameter(name: "open", expression: 80)]),
            FakeAssemblySolver()
        )
        let wide = try await rebuild(
            document(.slider, value: 90, limits: limits, parameters: [Parameter(name: "open", expression: 100)]),
            FakeAssemblySolver()
        )

        #expect(narrow.assembly?.joints.first?.status == .failed("value 90 mm is outside its limits 0 mm…80 mm"))
        #expect(wide.assembly?.joints.first?.status == .ok)
    }

    @Test("A minimum above the maximum fails the joint")
    func minAboveMax() async throws {
        let result = try await rebuild(
            document(.revolute, limits: JointLimits(min: 90, max: 0)), FakeAssemblySolver()
        )
        #expect(result.assembly?.joints.first?.status == .failed("limits min 90° is above max 0°"))
    }

    @Test("A value that does not evaluate fails the joint")
    func valueExpressionFails() async throws {
        let result = try await rebuild(document(.revolute, value: "missing"), FakeAssemblySolver())
        guard case let .failed(reason)? = result.assembly?.joints.first?.status else {
            Issue.record("the joint did not fail")
            return
        }
        #expect(reason.hasPrefix("value: "))
    }

    @Test("Instances report the freedoms their joints leave them")
    func instanceFreedoms() async throws {
        var free = document(.revolute)
        free.assembly?.instances.append(Instance(name: "Loose", part: part.id))
        let freeResult = try await rebuild(free, FakeAssemblySolver())
        let drivenResult = try await rebuild(document(.revolute, value: 10), FakeAssemblySolver())
        var unjoined = document(.revolute)
        unjoined.assembly?.joints = []
        let unjoinedResult = try await rebuild(unjoined, FakeAssemblySolver())

        #expect(freeResult.assembly?.instances.map(\.freedoms) == [0, 1, 6])
        #expect(drivenResult.assembly?.instances.map(\.freedoms) == [0, 0])
        #expect(unjoinedResult.assembly?.instances.map(\.freedoms) == [nil, nil])
    }

    @Test("A free hinge resting a hair below its minimum reads as the minimum, not a full turn above it")
    func measuredAngleSnapsToMinimum() async throws {
        let turn = simd_double3x3(simd_quatd(angle: -1e-12, axis: SIMD3(0, 0, 1)))
        let pivot = SIMD3<Double>(5, 10, 30)
        let turned = RigidTransform(rotation: turn, translation: pivot - turn * SIMD3(5, 10, 0))
        let solver = FakeAssemblySolver { assembly in
            var solution = FakeAssemblySolver.unchanged(assembly)
            solution.placements[assembly.joints[0].bodyB] = turned
            return solution
        }
        let result = try await rebuild(document(.revolute, limits: JointLimits(min: 0, max: 110)), solver)
        let value = try #require(result.assembly?.joints.first?.value)

        #expect(abs(value) < 1e-6)
        #expect(result.assembly?.joints.first?.isOutsideLimits == false)
    }
}
