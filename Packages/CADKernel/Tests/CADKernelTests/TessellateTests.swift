import simd
import Testing
@testable import CADKernel

@Suite("Tessellation")
struct TessellateTests {
    private func roundedBlock() throws -> Solid {
        let block = try Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5)
        return try Kernel.fillet(block, edges: .parallel(to: SIMD3(0, 0, 1)), radius: 0.1)
    }

    @Test("The mesh is a well-formed triangle list")
    func wellFormed() throws {
        let mesh = try Kernel.tessellate(roundedBlock())

        #expect(!mesh.positions.isEmpty)
        #expect(mesh.normals.count == mesh.positions.count)
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
    }

    @Test("Every vertex lies inside the solid's bounds")
    func insideBounds() throws {
        let solid = try roundedBlock()
        let metrics = try Kernel.metrics(of: solid)
        let mesh = try Kernel.tessellate(solid)

        let lower = SIMD3<Float>(metrics.boundsMin) - 1e-4
        let upper = SIMD3<Float>(metrics.boundsMax) + 1e-4
        #expect(mesh.positions.allSatisfy { all($0 .>= lower) && all($0 .<= upper) })
    }

    @Test("Triangles wind counter-clockwise when seen from outside")
    func outwardWinding() throws {
        let mesh = try Kernel.tessellate(roundedBlock())
        let centre = SIMD3<Float>(0, 0, 0.25)

        for start in stride(from: 0, to: mesh.indices.count, by: 3) {
            let (a, b, c) = (
                mesh.positions[Int(mesh.indices[start])],
                mesh.positions[Int(mesh.indices[start + 1])],
                mesh.positions[Int(mesh.indices[start + 2])]
            )
            let faceNormal = simd_cross(b - a, c - a)
            #expect(simd_dot(faceNormal, (a + b + c) / 3 - centre) > 0, "triangle at index \(start) winds inward")
        }
    }

    @Test("Vertex normals are unit length and point away from the convex block's centre")
    func outwardNormals() throws {
        let mesh = try Kernel.tessellate(roundedBlock())
        let centre = SIMD3<Float>(0, 0, 0.25)

        for (position, normal) in zip(mesh.positions, mesh.normals) {
            #expect(abs(simd_length(normal) - 1) < 1e-4)
            #expect(simd_dot(normal, position - centre) > 0, "normal at \(position) points inward")
        }
    }
}
