@testable import CADModel
import Foundation
import simd
import Testing

@Suite("Rigid transforms")
struct RigidTransformTests {
    private func close(_ a: SIMD3<Double>?, _ b: SIMD3<Double>, _ tolerance: Double = 1e-12) -> Bool {
        guard let a else { return false }
        return simd_distance(a, b) <= tolerance
    }

    @Test("Rotates about the axis through the origin, then translates")
    func rotatesThenTranslates() {
        let transform = RigidTransform(
            ResolvedPlacement(translation: SIMD3(10, 0, 0), rotationAxis: SIMD3(0, 0, 2), rotationDegrees: 90)
        )
        let moved: SIMD3<Double> = transform.point(SIMD3(1, 0, 0))
        let turned: SIMD3<Double> = transform.direction(SIMD3(1, 0, 0))

        #expect(close(moved, SIMD3(10, 1, 0)))
        #expect(close(turned, SIMD3(0, 1, 0)))
        #expect(RigidTransform(ResolvedPlacement()) == .identity)
    }

    @Test("A box's faces and edges move and turn, keeping their names")
    func topologyMoves() throws {
        let transform = RigidTransform(
            ResolvedPlacement(translation: SIMD3(0, 0, 5), rotationAxis: SIMD3(1, 0, 0), rotationDegrees: 90)
        )
        let topology = BodyTopology.box("Box", size: SIMD3(2, 4, 6)).transformed(by: transform)
        let top = try #require(topology.faces.first { $0.names == ["Box.top"] })
        let edge = try #require(topology.edges.first)
        let original = try #require(BodyTopology.box("Box", size: SIMD3(2, 4, 6)).edges.first)

        #expect(close(top.normal, SIMD3(0, -1, 0)))
        #expect(close(top.centroid, SIMD3(1, -6, 7)))
        #expect(close(edge.midpoint, transform.point(original.midpoint)))
        #expect(edge.faces == original.faces)
    }

    @Test("A mesh moves its positions and turns its normals")
    func meshMoves() {
        let mesh = BodyMesh(positions: [SIMD3(1, 0, 0)], normals: [SIMD3(1, 0, 0)], indices: [0, 0, 0])
        let transform = RigidTransform(
            ResolvedPlacement(translation: SIMD3(0, 0, 3), rotationAxis: SIMD3(0, 0, 1), rotationDegrees: 90)
        )
        let moved = mesh.transformed(by: transform)
        let position = SIMD3<Double>(moved.positions[0])
        let normal = SIMD3<Double>(moved.normals[0])

        #expect(close(position, SIMD3(0, 1, 3), 1e-6))
        #expect(close(normal, SIMD3(0, 1, 0), 1e-6))
        #expect(moved.indices == mesh.indices)
    }
}
