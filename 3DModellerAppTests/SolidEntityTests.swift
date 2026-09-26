import CADKernel
import Foundation
import RealityKit
import Testing
@testable import _D_Modeller

@Suite("Solid entities")
@MainActor
struct SolidEntityTests {
    let recipe = SolidRecipe(width: 0.4, height: 0.2, depth: 0.1, filletRadius: 0.02)

    private func expectBlockGeometry(_ entity: CADEntity, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let extents = try #require((entity.entity as? ModelEntity)?.model?.mesh.bounds.extents)
        #expect(abs(extents.x - 0.4) < 1e-3, sourceLocation: sourceLocation)
        #expect(abs(extents.y - 0.1) < 1e-3, sourceLocation: sourceLocation)
        #expect(abs(extents.z - 0.2) < 1e-3, sourceLocation: sourceLocation)
    }

    @Test("createSolid adds a selectable entity with the recipe")
    func createsEntity() throws {
        let scene = SceneManager()

        let entity = try scene.createSolid(recipe: recipe, name: "Bracket")

        #expect(scene.entities.count == 1)
        #expect(entity.type == .solid)
        #expect(entity.solid == recipe)
        #expect(entity.name == "Bracket")
    }

    @Test("A fillet that doesn't fit throws and leaves the scene unchanged")
    func failedFilletLeavesSceneAlone() throws {
        let scene = SceneManager()
        let impossible = SolidRecipe(width: 0.1, height: 0.1, depth: 0.1, filletRadius: 0.08)

        #expect(throws: KernelError.self) { try scene.createSolid(recipe: impossible) }
        #expect(scene.entities.isEmpty)
        #expect(scene.rootEntity.children.count == SceneManager().rootEntity.children.count)
    }

    @Test("Saving and loading keeps the block's recipe")
    func roundTrip() throws {
        let scene = SceneManager()
        _ = try scene.createSolid(recipe: recipe, name: "Bracket")

        let encoded = try JSONEncoder().encode(scene.toSceneData())
        let reloaded = SceneManager()
        reloaded.loadSceneData(try JSONDecoder().decode(SceneData.self, from: encoded))

        let entity = try #require(reloaded.entity(named: "Bracket"))
        #expect(entity.type == .solid)
        #expect(entity.solid == recipe)
        try expectBlockGeometry(entity)
    }

    @Test("Scene files written before solids existed still load")
    func legacyFile() throws {
        let legacy = """
            {"entities":[{"id":"6F1B3C2E-1111-4A6B-9C1D-2E3F4A5B6C7D","name":"OldBox","type":"box",
            "transform":{"position":[0,0,0],"rotation":[0,0,0],"scale":[1,1,1]},
            "material":{"color":{"r":0.8,"g":0.8,"b":0.8,"a":1},"metallic":0,"roughness":0.5},
            "isVisible":true}],
            "metadata":{"name":"Old","createdAt":0,"modifiedAt":0}}
            """
        let data = try JSONDecoder().decode(SceneData.self, from: Data(legacy.utf8))

        #expect(data.entities.first?.type == .box)
        #expect(data.entities.first?.solid == nil)
    }

    @Test("Undo after deleting a block brings back a block, not a box")
    func undoRestoresSolid() throws {
        let scene = SceneManager()
        let entity = try scene.createSolid(recipe: recipe, name: "Bracket")
        _ = scene.deleteEntity(id: entity.id)

        scene.undo()

        let restored = try #require(scene.entities.values.first { $0.name == "Bracket" })
        #expect(restored.type == .solid)
        #expect(restored.solid == recipe)
        try expectBlockGeometry(restored)
    }

    @Test("Duplicating a block copies its recipe")
    func duplicate() throws {
        let scene = SceneManager()
        let entity = try scene.createSolid(recipe: recipe, name: "Bracket")

        let copy = try #require(scene.duplicateEntity(id: entity.id))

        #expect(copy.type == .solid)
        #expect(copy.solid == recipe)
        try expectBlockGeometry(copy)
    }
}
