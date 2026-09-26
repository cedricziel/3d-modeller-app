import CADModel
import RealityKit

/// The model is millimetres with Z up; RealityKit is metres with Y up.
enum ViewportFrame {
    static let metresPerMillimetre: Float = 0.001

    static func sceneDirection(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(v.x, v.z, -v.y) }

    static func scenePosition(_ p: SIMD3<Float>) -> SIMD3<Float> { sceneDirection(p) * metresPerMillimetre }

    static func sceneBounds(of result: RebuildResult?, content: ViewportContent = .parts) -> SceneBounds? {
        let corners = (result?.displayBodies(content) ?? []).compactMap(\.metrics).flatMap { metrics in
            [metrics.boundsMin, metrics.boundsMax].map { scenePosition(SIMD3<Float>($0)) }
        }
        guard let first = corners.first else { return nil }
        return corners.dropFirst().reduce(SceneBounds(min: first, max: first)) {
            SceneBounds(min: simd_min($0.min, $1), max: simd_max($0.max, $1))
        }
    }
}

struct SceneBounds: Equatable {
    var min: SIMD3<Float>
    var max: SIMD3<Float>
}

extension BodyMesh {
    var meshDescriptor: MeshDescriptor {
        var descriptor = MeshDescriptor(name: "body")
        descriptor.positions = MeshBuffer(positions.map(ViewportFrame.scenePosition))
        descriptor.normals = MeshBuffer(normals.map(ViewportFrame.sceneDirection))
        descriptor.primitives = .triangles(indices)
        return descriptor
    }
}
