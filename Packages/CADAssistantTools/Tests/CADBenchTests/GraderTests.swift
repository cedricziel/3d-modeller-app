import CADModel
import CADModelKernel
import CADModelSolvers
import Foundation
import Testing

@testable import CADBench

@Suite("Grader")
struct GraderTests {
    let grader = Grader(kernel: OCCTGeometryKernel())

    private func grade(
        _ checks: [Check], _ document: CADDocument, reference: CADDocument? = nil, seed: CADDocument? = nil
    ) async -> Grade {
        await grader.grade(
            BenchTask(
                id: "t", kind: seed == nil ? .build : .modify, prompt: "p", checks: checks, seed: seed,
                reference: reference),
            document: document)
    }

    private func part(_ features: [Feature], parameters: [Parameter] = []) -> CADDocument {
        CADDocument(parameters: parameters, parts: [Part(name: "P", features: features)])
    }

    @Test("A correct box passes gate, count, bounds, volume, parameter and feature-count checks")
    func passingChecks() async {
        let document = part(
            [box("Block", "w", 20, 30, at: Vector3(1, 2, 3))], parameters: [Parameter(name: "w", expression: 10)])
        let result = await grade(
            [
                .gate, .bodyCount(1),
                .boundingBox(
                    BodySelector(body: "Body1"), min: SIMD3(1, 2, 3), max: SIMD3(11, 22, 33), size: SIMD3(10, 20, 30),
                    tolerance: 0.01),
                .volume(BodySelector(), expected: 6000, tolerance: 0.001),
                .parameter(name: "w", value: 10, tolerance: 1e-6),
                .featureCount(.box, min: 1, max: 1),
            ], document)
        #expect(result.passed, "\(result.failures)")
        #expect(result.outcomes.count == 6)
    }

    @Test("Wrong values fail with the measured value in the detail")
    func failingChecks() async {
        let document = part([box("Block", 10, 20, 30), box("Spare", 1, 1, 1, suppressed: true)])
        let result = await grade(
            [
                .bodyCount(2),
                .boundingBox(BodySelector(), min: nil, max: SIMD3(10, 20, 31), size: nil, tolerance: 0.01),
                .volume(BodySelector(), expected: 6100, tolerance: 0.01),
                .parameter(name: "t", value: 1, tolerance: 1e-6),
                .featureCount(.box, min: 2, max: nil),
            ], document)
        #expect(!result.passed)
        #expect(result.outcomes.allSatisfy { !$0.passed })
        #expect(
            result.outcomes.map(\.detail) == [
                "1 body", "min (0, 0, 0), max (10, 20, 30)", "6000 mm³", "no parameter named t", "1 box feature",
            ])
    }

    @Test("The gate fails on failed features, on broken bodies and on an empty model")
    func gateFailures() async {
        let failed = await grade(
            [.gate], part([box("Block", 10, 10, 10), box("Cut", 1, 1, 1, operation: .cut("Body7"))]))
        #expect(!failed.passed)
        #expect(failed.outcomes[0].detail.contains("Cut: failed: no body named 'Body7'"))

        let twoSolids = await grade(
            [.gate], part([box("A", 1, 1, 1), box("B", 1, 1, 1, at: Vector3(5, 0, 0), operation: .join("Body1"))]))
        #expect(twoSolids.outcomes[0].detail.contains("Body1: 2 solids"))

        let empty = await grade([.gate], part([]))
        #expect(empty.outcomes[0] == CheckOutcome(check: Check.gate.description, passed: false, detail: "no bodies"))
    }

    @Test("Selectors refuse unknown parts, unknown bodies and names shared by several parts")
    func selectorRefusals() async {
        let document = CADDocument(parts: [
            Part(name: "P", features: [box("A", 1, 1, 1)]), Part(name: "Q", features: [box("B", 2, 2, 2)]),
        ])
        let volume = { (selector: BodySelector) in Check.volume(selector, expected: 1, tolerance: 0.01) }
        let result = await grade(
            [
                volume(BodySelector(body: "Body1")), volume(BodySelector(body: "Body4")),
                volume(BodySelector(part: "R")), volume(BodySelector(part: "P", body: "Body1")),
            ],
            document)
        #expect(
            result.outcomes.map(\.detail) == [
                "Body1 exists in P, Q; name the part",
                "no body named Body4 (bodies: P/Body1, Q/Body1)",
                "no part named R (parts: P, Q)",
                "1 mm³",
            ])
        #expect(result.outcomes.map(\.passed) == [false, false, false, true])
    }

    @Test("Overlap is 1 for identical geometry and a third for a half-shifted cube")
    func overlapIdentical() async {
        let cube = part([box("Cube", 10, 10, 10)])
        let same = await grade([.referenceIoU(threshold: 0.999)], cube, reference: cube)
        #expect(same.passed, "\(same.failures)")

        let shifted = await grade(
            [.referenceIoU(threshold: 0.5)], part([box("Cube", 10, 10, 10, at: Vector3(5, 0, 0))]), reference: cube)
        #expect(!shifted.passed)
        #expect(shifted.outcomes[0].detail.hasPrefix("overlap 0.333"))

        let apart = await grade(
            [.referenceIoU(threshold: 0.5)], part([box("Cube", 10, 10, 10, at: Vector3(50, 0, 0))]), reference: cube)
        #expect(apart.outcomes[0].detail.hasPrefix("overlap 0 "))

        let empty = await grade([.referenceIoU(threshold: 0.5)], part([]), reference: cube)
        #expect(empty.outcomes[0].detail == "no bodies")
    }

    @Test("Unchanged-elsewhere reports the differences from the seed")
    func unchangedExcept() async {
        let seed = part(
            [box("Plate", "w", 10, 1), box("Hole", 1, 1, 1, operation: .cut("Body1"))],
            parameters: [Parameter(name: "w", expression: 20)])
        var edited = seed
        edited.parameters[0].expression = 30
        let result = await grade(
            [.unchangedExcept(features: ["Hole"], parameters: [], instances: [], joints: [], allowNewFeatures: false)],
            edited,
            seed: seed)
        #expect(
            result.outcomes[0]
                == CheckOutcome(
                    check: "unchanged except features Hole", passed: false,
                    detail: "parameter w changed from 20 to 30"))
    }

    private func stacked(topAt z: Scalar, extra: [Instance] = []) -> CADDocument {
        let plate = Part(name: "Plate", features: [box("Box", 60, 40, 5)])
        return CADDocument(
            parts: [plate],
            assembly: Assembly(
                instances: [
                    Instance(name: "Bottom", part: plate.id, grounded: true),
                    Instance(name: "Top", part: plate.id, placement: Placement(translation: Vector3(0, 0, z))),
                ] + extra))
    }

    @Test("Instance count, instance bounds and interference are graded on the placed instances")
    func instanceChecks() async {
        let checks: [Check] = [
            .gate, .instanceCount(2),
            .instanceBounds(instance: "Top", min: SIMD3(0, 0, 5), max: SIMD3(60, 40, 10), size: nil, tolerance: 0.01),
            .instanceBounds(instance: nil, min: SIMD3(0, 0, 0), max: SIMD3(60, 40, 10), size: nil, tolerance: 0.01),
            .noInterference,
        ]
        let touching = await grade(checks, stacked(topAt: 5))
        let sunk = await grade(checks, stacked(topAt: 3))

        #expect(touching.passed, "\(touching.failures)")
        #expect(sunk.outcomes.map(\.passed) == [true, true, false, false, false])
        #expect(sunk.outcomes[4].detail == "Bottom and Top overlap by 4800 mm³")
        #expect(touching.outcomes[4].detail == "no overlap")
    }

    @Test("A failed instance fails the gate; an unknown instance fails its bounds check")
    func failedInstances() async {
        var document = stacked(topAt: 5)
        document.assembly?.instances[1].body = "Body9"
        let result = await grade(
            [
                .gate,
                .instanceBounds(instance: "Lid", min: SIMD3(0, 0, 0), max: nil, size: nil, tolerance: 0.01),
            ], document)

        #expect(result.outcomes[0].detail == "instance Top: failed: part Plate has no body named Body9; bodies: Body1")
        #expect(result.outcomes[1].detail == "no instance named Lid (instances: Bottom, Top)")
    }

    @Test("Unchanged-elsewhere compares instances by name")
    func unchangedInstances() async {
        let seed = stacked(topAt: 5)
        var moved = seed
        moved.assembly?.instances[1].placement.translation.z = 25
        moved.assembly?.instances[0].grounded = false
        let result = await grade(
            [.unchangedExcept(features: [], parameters: [], instances: ["Top"], joints: [], allowNewFeatures: false)],
            moved,
            seed: seed)

        #expect(result.outcomes[0].detail == "instance Bottom changed")
    }

    @Test("Reference overlap compares the placed instances when the reference has an assembly")
    func instanceOverlap() async {
        let same = await grade([.referenceIoU(threshold: 0.999)], stacked(topAt: 5), reference: stacked(topAt: 5))
        let moved = await grade([.referenceIoU(threshold: 0.999)], stacked(topAt: 10), reference: stacked(topAt: 5))

        #expect(same.passed, "\(same.failures)")
        #expect(!moved.passed)
    }

    /// The stacked plates with Top held on Bottom by a fixed joint, or by a joint to a face that does not exist.
    private func joined(face: String = "Box.top", kind: JointKind = .fixed) -> CADDocument {
        var document = stacked(topAt: 0)
        let (bottom, top) = (document.instances[0].id, document.instances[1].id)
        document.assembly?.joints = [
            Joint(
                name: "Rest", kind: kind, a: JointFrameRef(instance: bottom, face: .name(face)),
                b: JointFrameRef(instance: top, face: .name("Box.bottom")))
        ]
        return document
    }

    private var solving: Grader<OCCTGeometryKernel> {
        Grader(kernel: OCCTGeometryKernel(), assemblySolver: OndselAssemblySolver())
    }

    private func gradeSolved(_ checks: [Check], _ document: CADDocument) async -> Grade {
        await solving.grade(BenchTask(id: "t", kind: .build, prompt: "p", checks: checks), document: document)
    }

    @Test("Joints are graded on the solved assembly: satisfied, kinds and the instances' relative position")
    func jointChecks() async {
        let offset = SIMD3<Double>(0, 0, 5)
        let passing = await gradeSolved(
            [
                .gate, .jointsSatisfied(minimum: 1, kinds: [.fixed]),
                .instancePosition(instance: "Top", relativeTo: "Bottom", translation: offset, tolerance: 1e-6),
                .instancePosition(instance: "Top", relativeTo: nil, translation: offset, tolerance: 1e-6),
            ], joined())
        let wrongKind = await gradeSolved([.jointsSatisfied(minimum: 1, kinds: [.revolute])], joined())
        let tooFew = await gradeSolved([.jointsSatisfied(minimum: 2, kinds: [])], joined())
        let none = await gradeSolved([.jointsSatisfied(minimum: 1, kinds: [])], stacked(topAt: 5))
        let moved = await gradeSolved(
            [.instancePosition(instance: "Top", relativeTo: "Bottom", translation: SIMD3(0, 0, 6), tolerance: 0.01)],
            joined())

        #expect(passing.passed, "\(passing.failures)")
        #expect(wrongKind.outcomes[0].detail == "1 joint (fixed); no revolute joint")
        #expect(!tooFew.passed)
        #expect(none.outcomes[0].detail == "no joints")
        #expect(moved.outcomes[0].detail == "Top is at (0, 0, 5) from Bottom")
    }

    @Test("A failed joint fails the gate and the joints check")
    func failedJoint() async {
        let result = await gradeSolved([.gate, .jointsSatisfied(minimum: 1, kinds: [])], joined(face: "Box.nope"))

        #expect(!result.outcomes[0].passed)
        #expect(result.outcomes[0].detail.contains("joint Rest: failed: a: "))
        #expect(result.outcomes[1].detail.hasPrefix("Rest: failed: a: "))
    }

    @Test("Unchanged-elsewhere compares joints by name")
    func unchangedJoints() async {
        let seed = joined()
        var edited = seed
        edited.assembly?.joints[0].flip = true
        let changed = await gradeSolved(
            [.unchangedExcept(features: [], parameters: [], instances: [], joints: [], allowNewFeatures: false)],
            edited)
        let exempt = await grade(
            [.unchangedExcept(features: [], parameters: [], instances: [], joints: ["Rest"], allowNewFeatures: false)],
            edited, seed: seed)
        let fresh = await grade(
            [.unchangedExcept(features: [], parameters: [], instances: [], joints: [], allowNewFeatures: false)],
            edited, seed: seed)

        #expect(changed.outcomes[0].detail == "the task has no seed")
        #expect(exempt.passed, "\(exempt.failures)")
        #expect(fresh.outcomes[0].detail == "joint Rest changed")
    }
}
