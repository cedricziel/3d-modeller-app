@testable import CADModel
import Foundation
import simd
import Testing

@Suite("Assembly rebuild")
struct AssemblyRebuildTests {
    let kernel = FakeKernel()
    var engine: RebuildEngine<FakeKernel> {
        RebuildEngine(kernel: kernel)
    }

    private func box(_ name: String, _ size: Scalar = 10) -> Feature {
        Feature(name: name, kind: .primitive(PrimitiveFeature(.box(width: size, depth: size, height: size))))
    }

    private func document(_ features: [Feature], _ instances: (UUID) -> [Instance], parameters: [Parameter] = [])
        -> CADDocument
    {
        let part = Part(name: "Plate", features: features)
        return CADDocument(parameters: parameters, parts: [part], assembly: Assembly(instances: instances(part.id)))
    }

    private func at(_ x: Scalar, _ y: Scalar, _ z: Scalar) -> Placement {
        Placement(translation: Vector3(x, y, z))
    }

    @Test("Instances move the part's bodies, meshes and faces without rebuilding the part")
    func placesInstances() async throws {
        let result = try await engine.rebuild(
            document([box("Box")]) { part in
                [
                    Instance(name: "Base", part: part, grounded: true),
                    Instance(name: "Lid", part: part, placement: at(0, 0, 20)),
                ]
            }
        )
        let assembly = try #require(result.assembly)
        let lid = try #require(assembly.instance(named: "Lid"))
        let top = try #require(lid.bodies.first?.topology?.faces.first { $0.names == ["Box.top"] })
        let firstPosition = try #require(lid.bodies.first?.mesh?.positions.first)
        let boxCalls = kernel.calls.filter { $0.hasPrefix("box") }

        #expect(assembly.instances.map(\.status) == [.ok, .ok])
        #expect(lid.bodies.map(\.name) == ["Body1"])
        #expect(top.centroid == SIMD3(5, 5, 30))
        #expect(firstPosition == SIMD3<Float>(0, 0, 20))
        #expect(lid.transform?.translation == SIMD3(0, 0, 20))
        #expect(boxCalls.count == 1)
        #expect(assembly.instance(id: lid.id) == lid)
        #expect(result.failedInstanceCount == 0)
    }

    @Test("A body the part does not build fails the instance, listing the bodies that exist")
    func missingBodyFails() async throws {
        let result = try await engine.rebuild(
            document([box("Box")]) { [Instance(name: "Lid", part: $0, body: "Body3")] }
        )
        let lid = try #require(result.assembly?.instances.first)

        #expect(lid.status == .failed("part Plate has no body named Body3; bodies: Body1"))
        #expect(lid.bodies.isEmpty)
        #expect(result.failedInstanceCount == 1)
    }

    @Test("A part whose features all failed has no bodies to place")
    func brokenPartBodyFailsInstance() async throws {
        let result = try await engine.rebuild(document([box("Box", -1)]) { [Instance(name: "Lid", part: $0)] })

        #expect(result.assembly?.instances.first?.status == .failed("part Plate has no bodies"))
    }

    @Test("An instance of a part that no longer exists fails")
    func missingPartFails() async throws {
        let result = try await engine.rebuild(document([box("Box")]) { _ in [Instance(name: "Ghost", part: UUID())] })

        #expect(result.assembly?.instances.first?.status == .failed("its part no longer exists"))
    }

    @Test("A repeated name and a placement expression that does not evaluate each fail their instance")
    func duplicateAndExpressionFailures() async throws {
        let result = try await engine.rebuild(
            document([box("Box")]) { part in
                [
                    Instance(name: "A", part: part),
                    Instance(name: "A", part: part),
                    Instance(name: "B", part: part, placement: at(0, 0, "nope * 2")),
                ]
            }
        )
        let statuses = try #require(result.assembly?.instances.map(\.status))

        #expect(statuses[0] == .ok)
        #expect(statuses[1] == .failed("another instance is already named 'A'"))
        guard case let .failed(message) = statuses[2] else {
            Issue.record("expected a failure, got \(statuses[2])")
            return
        }
        #expect(message.hasPrefix("placement.translation.z: "))
    }

    @Test("A document without an assembly has no assembly result")
    func noAssemblyNoResult() async throws {
        let result = try await engine.rebuild(CADDocument(parts: [Part(name: "P", features: [box("Box")])]))

        #expect(result.assembly == nil)
    }

    @Test("Instance bodies are measured under the instance's id")
    func geometryKeysInstances() async throws {
        let document = document([box("Box")]) { part in
            [Instance(name: "A", part: part), Instance(name: "B", part: part, placement: at(0, 0, 20))]
        }
        let geometry = try await engine.build(document).geometry
        let (a, b) = (document.instances[0].id, document.instances[1].id)
        let distance = try geometry.distance(
            .body(BodyKey(owner: .instance(a), body: "Body1")), .body(BodyKey(owner: .instance(b), body: "Body1"))
        )

        #expect(distance.distance == 0)
        #expect(kernel.calls.contains("transform 1000 @(0,0,20) 0°(0,0,1)"))
    }

    @Test("Each placed instance's moved bodies are available as solids")
    func instanceSolids() async throws {
        let document = document([box("Box"), box("Knob", 2)]) { part in
            [Instance(name: "A", part: part), Instance(name: "B", part: part, body: "Body2")]
        }
        let solids = try await engine.instanceSolids(of: document)

        #expect(solids.map { "\($0.part)/\($0.name)" } == ["A/Body1", "A/Body2", "B/Body2"])
    }
}
