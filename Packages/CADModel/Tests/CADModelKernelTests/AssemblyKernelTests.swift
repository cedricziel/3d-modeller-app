import CADModel
import CADModelKernel
import Foundation
import simd
import Testing

@Suite("Assemblies on the OCCT kernel")
struct AssemblyKernelTests {
    let kernel = OCCTGeometryKernel()
    var engine: RebuildEngine<OCCTGeometryKernel> {
        RebuildEngine(kernel: kernel)
    }

    private func plate(_ instances: (UUID) -> [Instance]) -> CADDocument {
        let part = Part(
            name: "Plate",
            features: [
                Feature(name: "Box", kind: .primitive(PrimitiveFeature(.box(width: 60, depth: 40, height: 10))))
            ]
        )
        return CADDocument(parts: [part], assembly: Assembly(instances: instances(part.id)))
    }

    @Test("A rotated instance's moved faces match the kernel's own description of the moved body")
    func rotatedInstanceMatchesKernel() async throws {
        let placement = Placement(
            translation: Vector3(100, 0, 0), rotationAxis: Vector3(0, 0, 1), rotationDegrees: 90
        )
        let document = plate { [Instance(name: "Turned", part: $0, placement: placement)] }
        let result = try await engine.rebuild(document)
        let instance = try #require(result.assembly?.instances.first)
        let body = try #require(instance.bodies.first)
        let metrics = try #require(body.metrics)
        let moved = try #require(body.topology)

        let solid = try #require(try await engine.solids(of: document).first).body
        let resolved = ResolvedPlacement(
            translation: SIMD3(100, 0, 0), rotationAxis: SIMD3(0, 0, 1), rotationDegrees: 90
        )
        let expected = try kernel.topology(of: kernel.transform(solid, by: resolved))

        #expect(instance.status == .ok)
        #expect(simd_distance(metrics.boundsMin, SIMD3(60, 0, 0)) < 1e-3)
        #expect(simd_distance(metrics.boundsMax, SIMD3(100, 60, 10)) < 1e-3)
        #expect(moved.faces.map(\.names) == expected.faces.map(\.names))
        for (face, reference) in zip(moved.faces, expected.faces) {
            let centroidError: Double = simd_distance(face.centroid, reference.centroid)
            let normalError: Double = simd_distance(face.normal ?? .zero, reference.normal ?? .zero)
            #expect(centroidError < 1e-6)
            #expect(normalError < 1e-6)
        }
    }

    @Test("Two instances give two moved solids with the part's volume")
    func instanceSolidsVolume() async throws {
        let document = plate { part in
            [
                Instance(name: "A", part: part),
                Instance(name: "B", part: part, placement: Placement(translation: Vector3(0, 0, 10))),
            ]
        }
        let solids = try await engine.instanceSolids(of: document)
        let volumes = try solids.map { try kernel.metrics(of: $0.body).volume ?? 0 }
        let bounds = try kernel.metrics(of: solids[1].body)

        #expect(volumes.count == 2)
        #expect(volumes.allSatisfy { abs($0 - 24000) < 1e-6 * 24000 })
        #expect(abs(bounds.boundsMin.z - 10) < 1e-3)
    }

    @Test("A rotated cylinder's side gives a frame along its moved axis")
    func frameOnRotatedCylinder() async throws {
        let part = Part(
            name: "Pin",
            features: [Feature(name: "Pin", kind: .primitive(PrimitiveFeature(.cylinder(radius: 3, height: 20))))])
        let placement = Placement(
            translation: Vector3(0, 0, 50), rotationAxis: Vector3(1, 0, 0), rotationDegrees: 90)
        let document = CADDocument(
            parts: [part], assembly: Assembly(instances: [Instance(name: "P1", part: part.id, placement: placement)]))
        let instance = try #require(try await engine.rebuild(document).assembly?.instances.first)
        let frame = try instance.frame(
            face: .name("Pin.side"), edge: nil, body: nil, parameters: ParameterTable([]))
        let alongY: Double = abs(simd_dot(frame.zAxis, SIMD3(0, 1, 0)))
        let offAxis: Double = simd_distance(SIMD3(frame.origin.x, 0, frame.origin.z), SIMD3(0, 0, 50))

        #expect(abs(alongY - 1) < 1e-9)
        #expect(offAxis < 1e-6)
        #expect(abs(abs(frame.origin.y) - 10) < 1e-3)
    }
}
