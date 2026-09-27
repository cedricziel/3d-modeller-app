import CADModel
import RealityKit
import SwiftUI

@MainActor
final class ViewportScene {
    let root = Entity()
    private let bodies = Entity()
    private let sketches = Entity()
    private static let sketchLine = MeshResource.generateBox(size: 1)
    private static let sketchMaterial = UnlitMaterial(color: NSColor(red: 1, green: 0.62, blue: 0.2, alpha: 1))
    private static let constructionMaterial = UnlitMaterial(color: NSColor(white: 0.6, alpha: 1))
    /// Line thickness in scene metres (0.3 mm).
    private static let lineWidth: Float = 0.0003

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
        root.addChild(sketches)
    }

    var sketchSegmentCount: Int { sketches.children.count }

    var bodyEntities: [ModelEntity] { bodies.children.compactMap { $0 as? ModelEntity } }

    func show(_ result: RebuildResult?, content: ViewportContent = .parts) {
        bodies.children.removeAll()
        for (index, body) in (result?.displayBodies(content) ?? []).enumerated() {
            guard let resource = try? MeshResource.generate(from: [body.mesh.meshDescriptor]) else { continue }
            var material = SimpleMaterial(
                color: body.appearance.map { NSColor($0.color) } ?? Self.palette[index % Self.palette.count],
                roughness: .float(Float(body.appearance?.roughness ?? 0.6)), isMetallic: false)
            material.metallic = .float(Float(body.appearance?.metallic ?? 0))
            let entity = ModelEntity(mesh: resource, materials: [material])
            entity.name = body.name
            bodies.addChild(entity)
        }
        showSketches(content == .parts ? result : nil)
    }

    private func showSketches(_ result: RebuildResult?) {
        sketches.children.removeAll()
        for sketch in result?.parts.flatMap(\.sketches) ?? [] {
            for segment in SketchDisplay.segments(of: sketch) {
                let start = ViewportFrame.scenePosition(segment.start)
                let end = ViewportFrame.scenePosition(segment.end)
                let length = simd_distance(start, end)
                guard length > 0 else { continue }
                let line = ModelEntity(
                    mesh: Self.sketchLine,
                    materials: [segment.construction ? Self.constructionMaterial : Self.sketchMaterial])
                line.position = (start + end) / 2
                line.orientation = simd_quatf(from: SIMD3(1, 0, 0), to: (end - start) / length)
                line.scale = SIMD3(length, Self.lineWidth, Self.lineWidth)
                sketches.addChild(line)
            }
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
