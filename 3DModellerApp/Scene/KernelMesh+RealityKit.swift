import CADKernel
import RealityKit

extension KernelMesh {
    /// The kernel models Z-up; RealityKit is Y-up.
    var meshDescriptor: MeshDescriptor {
        let toYUp = { (v: SIMD3<Float>) in SIMD3(v.x, v.z, -v.y) }
        var descriptor = MeshDescriptor(name: "solid")
        descriptor.positions = MeshBuffer(positions.map(toYUp))
        descriptor.normals = MeshBuffer(normals.map(toYUp))
        descriptor.primitives = .triangles(indices)
        return descriptor
    }
}
