import CADKernel
import RealityKit

extension KernelMesh {
    var meshDescriptor: MeshDescriptor {
        var descriptor = MeshDescriptor(name: "solid")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return descriptor
    }
}
