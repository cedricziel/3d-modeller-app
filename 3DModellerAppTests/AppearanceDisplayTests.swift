@testable import _D_Modeller
import AppKit
import CADModel
import CADModelKernel
import RealityKit
import SwiftUI
import Testing

@Suite("Appearance display")
@MainActor
struct AppearanceDisplayTests {
    private let green = Appearance(color: HexColor(red: 0x2E, green: 0x7D, blue: 0x32))

    private func document() throws -> CADDocument {
        let part = Part(
            name: "Ornament",
            features: [
                Feature(name: "Box", kind: .primitive(PrimitiveFeature(.box(width: 10, depth: 10, height: 10))))
            ],
            appearance: green
        )
        let red = try Appearance(color: HexColor(red: 0xC6, green: 0x28, blue: 0x28), metallic: 1, roughness: 0.2)
        return CADDocument(
            parts: [part],
            assembly: Assembly(instances: [
                Instance(name: "O1", part: part.id), Instance(name: "O2", part: part.id, appearance: red),
            ])
        )
    }

    private func rgb(_ entity: ModelEntity) -> SIMD3<Int>? {
        guard let material = entity.model?.materials.first as? SimpleMaterial,
            let tint = material.color.tint.usingColorSpace(.sRGB)
        else { return nil }
        return SIMD3(
            Int((tint.redComponent * 255).rounded()), Int((tint.greenComponent * 255).rounded()),
            Int((tint.blueComponent * 255).rounded())
        )
    }

    private func scalar(_ parameter: MaterialScalarParameter) -> Float? {
        if case .float(let value) = parameter { value } else { nil }
    }

    @Test("Bodies carry the appearance they are shown in: the part's, or the instance's own")
    func displayBodies() async throws {
        let result = try await RebuildEngine(kernel: OCCTGeometryKernel()).rebuild(document())

        #expect(result.displayBodies(.parts).map(\.appearance) == [green])
        #expect(result.displayBodies(.assembly).map { $0.appearance?.color.hex } == ["#2E7D32", "#C62828"])
    }

    @Test("The viewport draws each body in its appearance's colour, metallic and roughness")
    func viewportMaterials() async throws {
        let result = try await RebuildEngine(kernel: OCCTGeometryKernel()).rebuild(document())
        let scene = ViewportScene()

        scene.show(result, content: .assembly)
        let entities = scene.bodyEntities
        let red = try #require(entities.last?.model?.materials.first as? SimpleMaterial)

        #expect(entities.map(rgb) == [SIMD3(0x2E, 0x7D, 0x32), SIMD3(0xC6, 0x28, 0x28)])
        #expect(scalar(red.metallic) == 1)
        #expect(scalar(red.roughness) == 0.2)
    }

    @Test("A picked colour becomes the nearest 8-bit hex colour")
    func pickedColour() {
        #expect(HexColor(Color(red: 0xC6 / 255.0, green: 0x28 / 255.0, blue: 0x28 / 255.0))?.hex == "#C62828")
        #expect(HexColor(Color(HexColor(red: 0x2E, green: 0x7D, blue: 0x32)))?.hex == "#2E7D32")
    }
}
