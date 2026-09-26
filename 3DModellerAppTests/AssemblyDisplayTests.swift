@testable import _D_Modeller
import CADModel
import CADAssistantTools
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

    private var mated: CADDocument {
        var document = assembled
        let (base, lid) = (document.instances[0].id, document.instances[1].id)
        document.assembly?.instances[1].placement = Placement(translation: Vector3(100, 0, 80))
        document.assembly?.joints = [
            Joint(
                name: "Seat", kind: .fixed, a: JointFrameRef(instance: base, face: .name("Box.top")),
                b: JointFrameRef(instance: lid, face: .name("Box.bottom")))
        ]
        return document
    }

    @Test("Selecting a joint shows the assembly")
    func followingJoint() {
        let document = mated
        #expect(ViewportContent.following(selection: document.joints[0].id, in: document) == .assembly)
    }

    @Test("The app's session solves joints, so the viewport shows the lid where the joint puts it")
    func solvedPlacementShown() async throws {
        let session = CADSession.forApp(document: mated)
        let result = try await session.rebuild()
        let lid = try #require(result.displayBodies(.assembly).last)
        let lowest = try #require(lid.mesh.positions.map(\.z).min())
        let leftmost = try #require(lid.mesh.positions.map(\.x).min())

        #expect(result.assembly?.joints.first?.status == .ok)
        #expect(abs(lowest - 5) < 1e-4)
        #expect(abs(leftmost) < 1e-4)
    }
}
