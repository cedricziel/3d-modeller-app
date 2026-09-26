import CADModel
import CADModelKernel
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
            [.unchangedExcept(features: ["Hole"], parameters: [], allowNewFeatures: false)], edited, seed: seed)
        #expect(
            result.outcomes[0]
                == CheckOutcome(
                    check: "unchanged except features Hole", passed: false,
                    detail: "parameter w changed from 20 to 30"))
    }
}
