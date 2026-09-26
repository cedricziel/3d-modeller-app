import CADModel
import CADModelKernel
import RealityKit
import Testing
@testable import _D_Modeller

@Suite("Viewport frame")
@MainActor
struct ViewportFrameTests {
    @Test("Model millimetres, Z-up, become scene metres, Y-up")
    func positions() {
        #expect(simd_distance(ViewportFrame.scenePosition(SIMD3(1000, 2000, 3000)), SIMD3(1, 3, -2)) < 1e-6)
        #expect(ViewportFrame.sceneDirection(SIMD3(0, 0, 1)) == SIMD3(0, 1, 0))
    }

    @Test("A body mesh becomes a Y-up MeshResource with normals rotated alongside")
    func meshDescriptor() throws {
        let mesh = BodyMesh(
            positions: [SIMD3(0, 0, 100), SIMD3(100, 0, 100), SIMD3(0, 50, 100)],
            normals: Array(repeating: SIMD3(0, 0, 1), count: 3),
            indices: [0, 1, 2])
        let descriptor = mesh.meshDescriptor
        let normals = Array(try #require(descriptor.normals?.elements))
        #expect(normals.allSatisfy { $0 == SIMD3(0, 1, 0) })
        let bounds = try MeshResource.generate(from: [descriptor]).bounds
        #expect(abs(bounds.min.y - 0.1) < 1e-6)
        #expect(abs(bounds.extents.x - 0.1) < 1e-6)
        #expect(abs(bounds.extents.z - 0.05) < 1e-6)
    }

    private func rebuild(_ document: CADDocument) async throws -> RebuildResult {
        try await RebuildEngine(kernel: OCCTGeometryKernel()).rebuild(document)
    }

    @Test("An empty result has no bounds")
    func emptyResultHasNoBounds() async throws {
        #expect(ViewportFrame.sceneBounds(of: nil) == nil)
        #expect(ViewportFrame.sceneBounds(of: try await rebuild(CADDocument())) == nil)
    }

    @Test("Scene bounds and entities come from real bodies")
    func sceneShowsBodies() async throws {
        let box = Feature(name: "B", kind: .primitive(PrimitiveFeature(.box(width: 100, depth: 50, height: 20))))
        let result = try await rebuild(CADDocument(parts: [Part(name: "P", features: [box])]))
        let bounds = try #require(ViewportFrame.sceneBounds(of: result))
        #expect(abs(bounds.min.z - -0.05) < 1e-4)
        #expect(abs(bounds.max.y - 0.02) < 1e-4)
        let scene = ViewportScene()
        scene.show(result)
        #expect(scene.bodyEntities.map(\.name) == ["Body1"])
        scene.show(nil)
        #expect(scene.bodyEntities.isEmpty)
    }
}
