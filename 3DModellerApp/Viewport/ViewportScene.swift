import CADModel
import RealityKit
import SwiftUI

@MainActor
final class ViewportScene {
    let root = Entity()
    private let bodies = Entity()

    private static let palette: [NSColor] = [
        NSColor(red: 0.62, green: 0.70, blue: 0.80, alpha: 1),
        NSColor(red: 0.80, green: 0.66, blue: 0.52, alpha: 1),
        NSColor(red: 0.60, green: 0.78, blue: 0.62, alpha: 1),
        NSColor(red: 0.78, green: 0.62, blue: 0.76, alpha: 1),
    ]

    init() {
        root.addChild(Self.makeGrid())
        root.addChild(Self.makeLight())
        root.addChild(bodies)
    }

    var bodyEntities: [ModelEntity] { bodies.children.compactMap { $0 as? ModelEntity } }

    func show(_ result: RebuildResult?) {
        bodies.children.removeAll()
        for (index, body) in (result?.bodies ?? []).enumerated() {
            guard let mesh = body.mesh, mesh.triangleCount > 0,
                let resource = try? MeshResource.generate(from: [mesh.meshDescriptor])
            else { continue }
            let material = SimpleMaterial(
                color: Self.palette[index % Self.palette.count], roughness: 0.6, isMetallic: false)
            let entity = ModelEntity(mesh: resource, materials: [material])
            entity.name = body.name
            bodies.addChild(entity)
        }
    }

    private static func makeGrid() -> Entity {
        let grid = Entity()
        let halfExtent: Float = 0.25
        let spacing: Float = 0.01
        let material = SimpleMaterial(color: .gray.withAlphaComponent(0.3), isMetallic: false)
        for offset in stride(from: -halfExtent, through: halfExtent, by: spacing) {
            let alongX = ModelEntity(
                mesh: .generateBox(width: halfExtent * 2, height: 0.0002, depth: 0.0002), materials: [material])
            alongX.position = [0, 0, offset]
            let alongZ = ModelEntity(
                mesh: .generateBox(width: 0.0002, height: 0.0002, depth: halfExtent * 2), materials: [material])
            alongZ.position = [offset, 0, 0]
            grid.addChild(alongX)
            grid.addChild(alongZ)
        }
        return grid
    }

    private static func makeLight() -> Entity {
        let light = DirectionalLight()
        light.light.intensity = 3000
        light.look(at: .zero, from: [0.4, 1, 0.7], relativeTo: nil)
        return light
    }
}
