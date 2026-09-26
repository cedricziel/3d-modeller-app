import Foundation
import Testing
@testable import CADModel

@Suite("Rebuild engine")
struct RebuildEngineTests {
    let kernel = FakeKernel()
    var engine: RebuildEngine<FakeKernel> { RebuildEngine(kernel: kernel) }

    private func box(
        _ name: String, _ w: Scalar = 10, _ d: Scalar = 10, _ h: Scalar = 10,
        placement: Placement = .identity, operation: SolidOperation = .newBody, suppressed: Bool = false
    ) -> Feature {
        Feature(
            name: name, suppressed: suppressed,
            kind: .primitive(
                PrimitiveFeature(.box(width: w, depth: d, height: h), placement: placement, operation: operation)))
    }

    private func rebuild(_ features: [Feature], parameters: [Parameter] = []) async throws -> PartResult {
        let result = try await engine.rebuild(
            CADDocument(parameters: parameters, parts: [Part(name: "P", features: features)]))
        return try #require(result.parts.first)
    }

    @Test("Primitives become numbered bodies with evaluated dimensions and degree placements")
    func primitives() async throws {
        let part = try await rebuild(
            [
                box("A", "w", 2, 3, placement: Placement(translation: Vector3(1, "w", 0), rotationDegrees: 90)),
                Feature(name: "B", kind: .primitive(PrimitiveFeature(.cylinder(radius: 1, height: "w * 2")))),
            ],
            parameters: [Parameter(name: "w", expression: 5)])
        #expect(part.features.map(\.status) == [.ok, .ok])
        #expect(part.features.map(\.body) == ["Body1", "Body2"])
        #expect(part.bodies.map(\.name) == ["Body1", "Body2"])
        #expect(part.bodies[0].metrics?.volume == 30)
        #expect(part.bodies[0].mesh?.triangleCount == 1)
        #expect(kernel.calls.first == "box 5x2x3 @(1,5,0) 90°(0,0,1)")
        #expect(kernel.calls[1] == "cylinder r1 h10 @(0,0,0) 0°(0,0,1)")
    }

    @Test("Cut, join and intersect modify the named body in place")
    func operations() async throws {
        let part = try await rebuild([
            box("A", 10, 10, 10),
            box("B", 1, 1, 1, operation: .cut("Body1")),
            box("C", 2, 1, 1, operation: .join("Body1")),
            box("D", 3, 1, 1, operation: .intersect("Body1")),
        ])
        #expect(part.features.map(\.status) == [.ok, .ok, .ok, .ok])
        #expect(part.features.map(\.body) == ["Body1", "Body1", "Body1", "Body1"])
        #expect(part.bodies.map(\.name) == ["Body1"])
        #expect(part.bodies[0].metrics?.volume == 3)
    }

    @Test("A boolean folds its tools into the target and consumes them")
    func booleanFolds() async throws {
        let part = try await rebuild([
            box("A", 10, 10, 10), box("B", 1, 1, 1), box("C", 2, 1, 1),
            Feature(
                name: "Cut",
                kind: .boolean(BooleanFeature(operation: .subtract, target: "Body1", tools: ["Body2", "Body3"]))),
            Feature(
                name: "Again", kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: ["Body2"]))),
        ])
        #expect(kernel.calls.suffix(2) == ["subtract 1000 1", "subtract 999 2"])
        #expect(part.bodies.map(\.name) == ["Body1"])
        #expect(part.bodies[0].metrics?.volume == 997)
        #expect(part.features[4].status == .failed(.bodyConsumed("Body2", by: "Cut")))
    }

    @Test(
        "Booleans with no tools, the target as a tool, or repeated tools fail",
        arguments: [
            [String](), ["Body1"], ["Body2", "Body2"],
        ])
    func invalidTools(tools: [String]) async throws {
        let part = try await rebuild([
            box("A"), box("B"),
            Feature(name: "X", kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: tools))),
        ])
        guard case .failed(.invalidTools) = part.features[2].status else {
            Issue.record("expected invalidTools, got \(part.features[2].status)")
            return
        }
        #expect(part.bodies.count == 2)
    }

    @Test("Transforms move a body")
    func transform() async throws {
        let part = try await rebuild([
            box("A"),
            Feature(
                name: "Move",
                kind: .transform(
                    TransformFeature(
                        body: "Body1",
                        placement: Placement(
                            translation: Vector3(0, 0, 5), rotationAxis: Vector3(1, 0, 0), rotationDegrees: 45)))),
        ])
        #expect(part.features[1].status == .ok)
        #expect(kernel.calls.last == "transform 1000 @(0,0,5) 45°(1,0,0)")
    }

    @Test("A kernel failure fails only that feature and leaves the body untouched")
    func kernelFailure() async throws {
        let part = try await rebuild([
            box("A", 10, 10, 10),
            box("Bad", 0, 1, 1, operation: .cut("Body1")),
            box("After", 1, 1, 1, operation: .cut("Body1")),
        ])
        #expect(part.features[1].status == .failed(.kernel("dimensions must be positive")))
        #expect(part.features[2].status == .ok)
        #expect(part.bodies[0].metrics?.volume == 999)
    }

    @Test("Dependents of a failed or suppressed body are skipped; unrelated features still build")
    func skipping() async throws {
        let part = try await rebuild([
            box("Broken", -1),
            box("Hidden", suppressed: true),
            box("UsesBroken", operation: .join("Body1")),
            box("UsesHidden", operation: .cut("Body2")),
            Feature(
                name: "Chain", kind: .boolean(BooleanFeature(operation: .union, target: "Body5", tools: ["Body1"]))),
            box("Fine"),
        ])
        #expect(
            part.features.map(\.status) == [
                .failed(.kernel("dimensions must be positive")),
                .suppressed,
                .skipped(dependsOn: "Broken"),
                .skipped(dependsOn: "Hidden"),
                .failed(.unknownBody("Body5")),
                .ok,
            ])
        #expect(part.features.map(\.body) == ["Body1", "Body2", "Body1", "Body2", "Body5", "Body3"])
        #expect(part.bodies.map(\.name) == ["Body3"])
    }

    @Test("A body that no feature has created yet is unknown")
    func unknownBody() async throws {
        let part = try await rebuild([box("A", operation: .cut("Body7")), box("B")])
        #expect(part.features[0].status == .failed(.unknownBody("Body7")))
        #expect(part.features[1].status == .ok)
    }

    @Test("A skipped new-body feature passes its root cause on")
    func skippedChain() async throws {
        let part = try await rebuild([
            box("Root", 0),
            Feature(
                name: "Grow", kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: ["Body1x"]))),
            box("Mid", operation: .cut("Body1")),
        ])
        #expect(part.features[2].status == .skipped(dependsOn: "Root"))
    }

    @Test("A duplicate feature name fails the later feature and still reserves its body number")
    func duplicateNames() async throws {
        let part = try await rebuild([box("A"), box("A"), box("B")])
        #expect(part.features.map(\.status) == [.ok, .failed(.duplicateName("A")), .ok])
        #expect(part.bodies.map(\.name) == ["Body1", "Body3"])
    }

    @Test("A feature using a broken parameter fails naming the field")
    func featureUsingBrokenParameterFails() async throws {
        let part = try await rebuild(
            [box("A", "loop"), box("B", 1, 1, "1/0"), box("C", "nope"), box("D", "ok")],
            parameters: [
                Parameter(name: "loop", expression: "loop + 1"), Parameter(name: "ok", expression: 2),
            ])
        #expect(
            part.features.map(\.status) == [
                .failed(.expression(field: "width", .failedParameter("loop"))),
                .failed(.expression(field: "height", .divisionByZero)),
                .failed(.expression(field: "width", .unknownName("nope"))),
                .ok,
            ])
    }

    @Test("Placement fields are named in expression errors")
    func placementErrors() async throws {
        let part = try await rebuild([box("A", placement: Placement(rotationDegrees: "x"))])
        #expect(part.features[0].status == .failed(.expression(field: "placement.rotationDegrees", .unknownName("x"))))
    }

    @Test("Parts rebuild independently with their own body names")
    func parts() async throws {
        let result = try await engine.rebuild(
            CADDocument(parts: [
                Part(name: "P1", features: [box("A")]), Part(name: "P2", features: [box("A"), box("B")]),
            ]))
        #expect(result.parts.map { $0.bodies.map(\.name) } == [["Body1"], ["Body1", "Body2"]])
        #expect(result.bodies.count == 3)
        #expect(result.triangleCount == 3)
        #expect(result.failedFeatureCount == 0)
    }

    @Test("The result exposes evaluated parameters and features by id")
    func lookups() async throws {
        let feature = box("A", 0)
        let result = try await engine.rebuild(
            CADDocument(
                parameters: [Parameter(name: "w", expression: "3 * 4")], parts: [Part(name: "P", features: [feature])]))
        #expect(result.parameters.value(of: "w") == .success(12))
        #expect(result.feature(id: feature.id)?.name == "A")
        #expect(result.failedFeatureCount == 1)
    }

    @Test("Rebuild runs off the main thread")
    @MainActor
    func offMain() async throws {
        _ = try await engine.rebuild(CADDocument(parts: [Part(name: "P", features: [box("A")])]))
        #expect(kernel.calls.count == 1)
        #expect(kernel.callsOnMainThread == 0)
    }

    @Test("Cancellation stops the rebuild between features")
    func cancellationStopsTheRebuild() async throws {
        let kernel = FakeKernel { _ in withUnsafeCurrentTask { $0?.cancel() } }
        let document = CADDocument(parts: [Part(name: "P", features: [box("A"), box("B")])])
        await #expect(throws: CancellationError.self) {
            try await RebuildEngine(kernel: kernel).rebuild(document)
        }
        #expect(kernel.calls.count == 1)
    }

    @Test("Statuses describe themselves for listings")
    func statusDescriptions() {
        #expect(FeatureStatus.ok.description == "ok")
        #expect(FeatureStatus.suppressed.description == "suppressed")
        #expect(FeatureStatus.skipped(dependsOn: "Box1").description == "skipped: depends on Box1")
        #expect(
            FeatureStatus.failed(.expression(field: "width", .unknownName("w"))).description
                == "failed: width: unknown parameter 'w'")
        #expect(
            FeatureStatus.failed(.bodyConsumed("Body2", by: "Cut1")).description
                == "failed: Body2 was used up as a tool by Cut1")
    }
}
