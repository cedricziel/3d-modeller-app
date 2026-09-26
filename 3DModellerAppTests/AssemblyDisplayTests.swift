@testable import _D_Modeller
import CADModel
import CADModelKernel
import Foundation
import Testing

@Suite("Assembly display")
@MainActor
struct AssemblyDisplayTests {
    private let plate = Part(
        name: "Plate",
        features: [Feature(name: "Box", kind: .primitive(PrimitiveFeature(.box(width: 60, depth: 40, height: 5))))]
    )

    private var assembled: CADDocument {
        CADDocument(
            parts: [plate],
            assembly: Assembly(instances: [
                Instance(name: "Base", part: plate.id, grounded: true),
                Instance(name: "Lid", part: plate.id, placement: Placement(translation: Vector3(0, 0, 20))),
            ])
        )
    }

    @Test("The viewport shows the assembly when there are instances, the parts otherwise")
    func automatic() {
        #expect(ViewportContent.automatic(for: assembled) == .assembly)
        #expect(ViewportContent.automatic(for: CADDocument(parts: [plate])) == .parts)
        #expect(ViewportContent.automatic(for: CADDocument(parts: [plate], assembly: Assembly())) == .parts)
    }

    @Test("Selecting a feature shows the parts; selecting an instance shows the assembly")
    func following() {
        let document = assembled
        let feature = document.parts[0].features[0].id
        let instance = document.instances[1].id

        #expect(ViewportContent.following(selection: feature, in: document) == .parts)
        #expect(ViewportContent.following(selection: instance, in: document) == .assembly)
        #expect(ViewportContent.following(selection: nil, in: document) == nil)
    }

    @Test("The assembly shows each instance's moved mesh under the instance's name")
    func displayBodies() async throws {
        let result = try await RebuildEngine(kernel: OCCTGeometryKernel()).rebuild(assembled)
        let instances = result.displayBodies(.assembly)
        let parts = result.displayBodies(.parts)
        let lidLowest = try #require(instances.last?.mesh.positions.map(\.z).min())

        #expect(instances.map(\.name) == ["Base", "Lid"])
        #expect(parts.map(\.name) == ["Body1"])
        #expect(abs(lidLowest - 20) < 1e-4)
        let bounds = try #require(ViewportFrame.sceneBounds(of: result, content: .assembly))
        #expect(abs(bounds.max.y - 0.025) < 1e-4)

        let scene = ViewportScene()
        scene.show(result, content: .assembly)
        #expect(scene.bodyEntities.map(\.name) == ["Base", "Lid"])
        #expect(scene.sketchSegmentCount == 0)
    }
}
