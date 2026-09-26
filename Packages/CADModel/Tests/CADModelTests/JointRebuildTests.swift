@testable import CADModel
import Foundation
import simd
import Testing

@Suite("Joint rebuild")
struct JointRebuildTests {
    private let part = Part(
        name: "Block",
        features: [Feature(name: "Box", kind: .primitive(PrimitiveFeature(.box(width: 10, depth: 20, height: 30))))])

    private func document(
        base: Placement = .identity, grounded: Bool = true, topBody: String? = nil, joints: (UUID, UUID) -> [Joint]
    ) -> CADDocument {
        let baseInstance = Instance(name: "Base", part: part.id, placement: base, grounded: grounded)
        let top = Instance(name: "Top", part: part.id, body: topBody)
        return CADDocument(
            parts: [part],
            assembly: Assembly(instances: [baseInstance, top], joints: joints(baseInstance.id, top.id)))
    }

    private func mate(
        _ base: UUID, _ top: UUID, name: String = "Mate", face: String = "Box.top", offset: JointOffset? = nil,
        flip: Bool = false
    ) -> Joint {
        Joint(
            name: name, kind: .fixed, a: JointFrameRef(instance: base, face: .name(face), offset: offset),
            b: JointFrameRef(instance: top, face: .name("Box.bottom")), flip: flip)
    }

    private func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool { simd_distance(a, b) < 1e-9 }

    private func rebuild(_ document: CADDocument, _ solver: (any AssemblySolving)?) async throws -> RebuildResult {
        try await RebuildEngine(kernel: FakeKernel(), assemblySolver: solver).rebuild(document)
    }

    @Test("Markers are frames on the part's own faces, not on the moved instance")
    func markersInPartCoordinates() async throws {
        let solver = FakeAssemblySolver()
        let raised = Placement(translation: Vector3(0, 0, 20))
        _ = try await rebuild(document(base: raised) { [mate($0, $1)] }, solver)
        let assembly = try #require(solver.received.first)
        let joint = try #require(assembly.joints.first)
        let marker = joint.markerA

        #expect(assembly.bodies.count == 2)
        #expect(assembly.bodies[joint.bodyA].grounded)
        #expect(assembly.bodies[joint.bodyA].placement.translation == SIMD3(0, 0, 20))
        #expect(close(marker.translation, SIMD3(5, 10, 30)))
        #expect(close(marker.rotation.columns.2, SIMD3(0, 0, 1)))
        #expect(close(marker.rotation.columns.0, SIMD3(1, 0, 0)))
    }

    @Test("Side b's frame turns half a turn about x so faces meet flush; flip keeps it")
    func mateTurnsSideB() async throws {
        let solver = FakeAssemblySolver()
        _ = try await rebuild(document { [mate($0, $1), mate($0, $1, name: "Flipped", flip: true)] }, solver)
        let joints = try #require(solver.received.first?.joints)
        let (turned, kept) = (joints[0].markerB.rotation, joints[1].markerB.rotation)

        #expect(close(joints[0].markerB.translation, SIMD3(5, 10, 0)))
        #expect(close(turned.columns.2, SIMD3(0, 0, 1)))
        #expect(close(turned.columns.0, SIMD3(1, 0, 0)))
        #expect(close(turned.columns.1, SIMD3(0, 1, 0)))
        #expect(close(kept.columns.2, SIMD3(0, 0, -1)))
    }

    @Test("An offset moves the frame along its own axes, then turns it about its z axis")
    func offsetApplied() async throws {
        let solver = FakeAssemblySolver()
        let offset = JointOffset(x: 1, z: 2, angle: 90)
        _ = try await rebuild(document { [mate($0, $1, offset: offset)] }, solver)
        let marker = try #require(solver.received.first?.joints.first?.markerA)

        #expect(close(marker.translation, SIMD3(6, 10, 32)))
        #expect(close(marker.rotation.columns.0, SIMD3(0, 1, 0)))
        #expect(close(marker.rotation.columns.2, SIMD3(0, 0, 1)))
    }

    @Test("A solved placement moves the instance; the document keeps its placement")
    func solvedPlacementMovesInstance() async throws {
        let solver = FakeAssemblySolver { assembly in
            var solution = FakeAssemblySolver.unchanged(assembly)
            solution.placements[1] = RigidTransform(rotation: matrix_identity_double3x3, translation: SIMD3(0, 0, 30))
            return solution
        }
        let document = document { [mate($0, $1)] }
        let model = try await RebuildEngine(kernel: FakeKernel(), assemblySolver: solver).build(document)
        let top = try #require(model.result.assembly?.instance(named: "Top"))
        let topFace = try #require(top.bodies.first?.topology?.faces.last)
        let joint = try #require(model.result.assembly?.joints.first)

        #expect(top.transform?.translation == SIMD3(0, 0, 30))
        #expect(top.movedByJoints)
        #expect(topFace.centroid == SIMD3(5, 10, 60))
        #expect(joint.status == .ok)
        #expect(document.instances[1].placement == .identity)
        #expect(model.result.assembly?.instance(named: "Base")?.movedByJoints == false)
    }

    @Test("Without an assembly solver every joint fails and nothing moves")
    func noSolver() async throws {
        let result = try await rebuild(document { [mate($0, $1)] }, nil)
        let joint = try #require(result.assembly?.joints.first)

        #expect(joint.status == .failed("no assembly solver is available"))
        #expect(result.assembly?.instance(named: "Top")?.transform == .identity)
        #expect(result.failedJointCount == 1)
    }

    @Test("Joints need a grounded instance")
    func noGroundedInstance() async throws {
        let solver = FakeAssemblySolver()
        let result = try await rebuild(document(grounded: false) { [mate($0, $1)] }, solver)

        #expect(
            result.assembly?.joints.first?.status == .failed("no instance is grounded; ground one with edit_instance"))
        #expect(solver.received.isEmpty)
    }

    @Test("A reference that matches nothing fails only its joint")
    func brokenReferenceFailsOnlyThatJoint() async throws {
        let solver = FakeAssemblySolver()
        let result = try await rebuild(
            document { [mate($0, $1, name: "Broken", face: "Box.nope"), mate($0, $1)] }, solver)
        let joints = try #require(result.assembly?.joints)
        guard case .failed(let reason) = joints[0].status else {
            Issue.record("expected a failure, got \(joints[0].status)")
            return
        }

        #expect(reason.hasPrefix("a: "))
        #expect(reason.contains("Box.nope"))
        #expect(joints[1].status == .ok)
        #expect(solver.received.first?.joints.count == 1)
    }

    @Test("A joint on an instance that did not build fails")
    func failedInstanceFailsJoint() async throws {
        let result = try await rebuild(document(topBody: "Body9") { [mate($0, $1)] }, FakeAssemblySolver())
        let status = try #require(result.assembly?.joints.first?.status)

        #expect(status == .failed("b: Top did not build: part Block has no body named Body9; bodies: Body1"))
    }

    @Test("The solver's verdicts become statuses")
    func verdictsReported() async throws {
        let solver = FakeAssemblySolver { assembly in
            var solution = FakeAssemblySolver.unchanged(assembly)
            solution.joints = [.conflicting, .redundant, .unsatisfied(distance: 4.25, angle: .pi / 2)]
            return solution
        }
        let result = try await rebuild(
            document { [mate($0, $1, name: "A"), mate($0, $1, name: "B"), mate($0, $1, name: "C")] }, solver)
        let statuses = try #require(result.assembly?.joints.map(\.status))
        let expected: [JointStatus] = [
            .failed("conflicts with other joints"), .redundant,
            .failed("not satisfied: origins 4.25 mm apart, axes 90° apart"),
        ]

        #expect(statuses == expected)
    }

    @Test("Joint names must be unique, and a joint needs two instances")
    func duplicateNameAndSameInstance() async throws {
        let result = try await rebuild(
            document { base, top in
                [mate(base, top), mate(base, top), mate(top, top, name: "Self")]
            }, FakeAssemblySolver())
        let statuses = try #require(result.assembly?.joints.map(\.status))

        #expect(statuses[1] == .failed("another joint is already named 'Mate'"))
        #expect(statuses[2] == .failed("both sides are on Top"))
    }

    @Test("A filter reference picks the part's own face, whatever the instance's starting placement")
    func filterResolvesInPartCoordinates() async throws {
        let solver = FakeAssemblySolver()
        let upsideDown = Placement(translation: Vector3(0, 0, 80), rotationAxis: Vector3(1, 0, 0), rotationDegrees: 180)
        let base = Instance(name: "Base", part: part.id, grounded: true)
        let top = Instance(name: "Top", part: part.id, placement: upsideDown)
        let joint = Joint(
            name: "Mate", kind: .fixed, a: JointFrameRef(instance: base.id, face: .name("Box.top")),
            b: JointFrameRef(instance: top.id, face: .filter("normal -Z")))
        let document = CADDocument(parts: [part], assembly: Assembly(instances: [base, top], joints: [joint]))
        _ = try await rebuild(document, solver)
        let marker = try #require(solver.received.first?.joints.first?.markerB)

        #expect(close(marker.translation, SIMD3(5, 10, 0)))
    }
}
