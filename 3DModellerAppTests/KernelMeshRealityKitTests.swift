import CADKernel
import RealityKit
import Testing
@testable import _D_Modeller

@Suite("KernelMesh → RealityKit")
@MainActor
struct KernelMeshRealityKitTests {
    @Test("A tessellated block becomes a Y-up MeshResource with the extrusion pointing up")
    func convertsToMeshResource() throws {
        let block = try Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5)
        let kernelMesh = try Kernel.tessellate(block)

        let resource = try MeshResource.generate(from: [kernelMesh.meshDescriptor])

        let bounds = resource.bounds
        #expect(abs(bounds.extents.x - 2) < 1e-3)
        #expect(abs(bounds.extents.y - 0.5) < 1e-3)
        #expect(abs(bounds.extents.z - 1) < 1e-3)
        #expect(abs(bounds.min.y) < 1e-3)
    }

    @Test("Normals are rotated with the positions")
    func rotatesNormals() throws {
        let kernelMesh = try Kernel.tessellate(Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.3))

        let descriptor = kernelMesh.meshDescriptor

        let positions = Array(try #require(descriptor.positions.elements as [SIMD3<Float>]?))
        let normals = Array(try #require(descriptor.normals?.elements))
        let upFacing = zip(positions, normals).filter { $0.1.y > 0.99 }.map(\.0)
        #expect(!upFacing.isEmpty)
        #expect(upFacing.allSatisfy { abs($0.y - 0.3) < 1e-4 })
    }
}
