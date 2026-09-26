import CADKernel
import RealityKit
import Testing
@testable import _D_Modeller

@Suite("KernelMesh → RealityKit")
@MainActor
struct KernelMeshRealityKitTests {
    @Test("A tessellated block becomes a MeshResource with the block's extents")
    func convertsToMeshResource() throws {
        let block = try Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5)
        let kernelMesh = try Kernel.tessellate(block)

        let resource = try MeshResource.generate(from: [kernelMesh.meshDescriptor])

        let extents = resource.bounds.extents
        #expect(abs(extents.x - 2) < 1e-3)
        #expect(abs(extents.y - 1) < 1e-3)
        #expect(abs(extents.z - 0.5) < 1e-3)
    }
}
