import Testing
import Foundation
@testable import _D_Modeller

@Suite("SceneDocument Tests")
struct SceneDocumentTests {

    // MARK: - Initialization Tests

    @Test("Empty document initialization")
    func testEmptyDocumentInit() {
        let doc = SceneDocument()

        #expect(doc.sceneData.entities.isEmpty)
        #expect(doc.sceneData.metadata.name == "Untitled Scene")
    }

    // MARK: - SceneData Tests

    @Test("SceneData default values")
    func testSceneDataDefaults() {
        let data = SceneData()

        #expect(data.entities.isEmpty)
        #expect(data.metadata.name == "Untitled Scene")
    }

    // MARK: - EntityData Tests

    @Test("EntityData initialization")
    func testEntityDataInit() {
        let entity = EntityData(
            name: "TestEntity",
            type: .box
        )

        #expect(entity.name == "TestEntity")
        #expect(entity.type == .box)
        #expect(entity.isVisible == true)
        #expect(entity.parentId == nil)
    }

    @Test("EntityData with custom transform")
    func testEntityDataWithTransform() {
        let transform = TransformData(
            position: [1, 2, 3],
            rotation: [0.1, 0.2, 0.3],
            scale: [2, 2, 2]
        )

        let entity = EntityData(
            name: "Transformed",
            type: .sphere,
            transform: transform
        )

        #expect(entity.transform.position == [1, 2, 3])
        #expect(entity.transform.scale == [2, 2, 2])
    }

    // MARK: - TransformData Tests

    @Test("TransformData default values")
    func testTransformDataDefaults() {
        let transform = TransformData()

        #expect(transform.position == .zero)
        #expect(transform.rotation == .zero)
        #expect(transform.scale == .one)
    }

    // MARK: - MaterialData Tests

    @Test("MaterialData default values")
    func testMaterialDataDefaults() {
        let material = MaterialData()

        #expect(material.color.r == 0.8)
        #expect(material.color.g == 0.8)
        #expect(material.color.b == 0.8)
        #expect(material.metallic == 0.0)
        #expect(material.roughness == 0.5)
    }

    @Test("MaterialData custom color")
    func testMaterialDataCustomColor() {
        let material = MaterialData(
            color: ColorData(r: 1.0, g: 0.0, b: 0.0),
            metallic: 0.9,
            roughness: 0.1
        )

        #expect(material.color.r == 1.0)
        #expect(material.metallic == 0.9)
        #expect(material.roughness == 0.1)
    }

    // MARK: - ColorData Tests

    @Test("ColorData RGB initialization")
    func testColorDataRGB() {
        let color = ColorData(r: 0.5, g: 0.6, b: 0.7)

        #expect(color.r == 0.5)
        #expect(color.g == 0.6)
        #expect(color.b == 0.7)
        #expect(color.a == 1.0)
    }

    @Test("ColorData RGBA initialization")
    func testColorDataRGBA() {
        let color = ColorData(r: 0.5, g: 0.6, b: 0.7, a: 0.8)

        #expect(color.a == 0.8)
    }

    @Test("ColorData named color - red")
    func testNamedColorRed() {
        let color = ColorData(named: "red")

        #expect(color.r == 1.0)
        #expect(color.g == 0.0)
        #expect(color.b == 0.0)
    }

    @Test("ColorData named color - green")
    func testNamedColorGreen() {
        let color = ColorData(named: "green")

        #expect(color.r == 0.0)
        #expect(color.g == 1.0)
        #expect(color.b == 0.0)
    }

    @Test("ColorData named color - blue")
    func testNamedColorBlue() {
        let color = ColorData(named: "blue")

        #expect(color.r == 0.0)
        #expect(color.g == 0.0)
        #expect(color.b == 1.0)
    }

    @Test("ColorData named color case insensitive")
    func testNamedColorCaseInsensitive() {
        let color1 = ColorData(named: "RED")
        let color2 = ColorData(named: "Red")
        let color3 = ColorData(named: "red")

        #expect(color1.r == color2.r)
        #expect(color2.r == color3.r)
    }

    @Test("ColorData unknown named color returns default")
    func testUnknownNamedColor() {
        let color = ColorData(named: "unknowncolor")

        #expect(color.r == 0.8)
        #expect(color.g == 0.8)
        #expect(color.b == 0.8)
    }

    // MARK: - JSON Encoding/Decoding Tests

    @Test("SceneData JSON round-trip")
    func testSceneDataJSONRoundTrip() throws {
        var original = SceneData()
        original.entities = [
            EntityData(name: "Box1", type: .box),
            EntityData(name: "Sphere1", type: .sphere)
        ]
        original.metadata.name = "Test Scene"

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SceneData.self, from: data)

        #expect(decoded.entities.count == 2)
        #expect(decoded.metadata.name == "Test Scene")
    }

    @Test("EntityData JSON round-trip preserves all properties")
    func testEntityDataJSONRoundTrip() throws {
        let original = EntityData(
            id: UUID(),
            name: "CompleteEntity",
            type: .cylinder,
            transform: TransformData(
                position: [1, 2, 3],
                rotation: [0.1, 0.2, 0.3],
                scale: [2, 2, 2]
            ),
            material: MaterialData(
                color: ColorData(r: 1, g: 0, b: 0),
                metallic: 0.5,
                roughness: 0.3
            ),
            parentId: nil,
            isVisible: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EntityData.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.type == original.type)
        #expect(decoded.transform.position == original.transform.position)
        #expect(decoded.material.metallic == original.material.metallic)
    }

    // MARK: - EntityType Tests

    @Test("All entity types are codable")
    func testEntityTypeCodable() throws {
        let types: [EntityData.EntityType] = [
            .box, .sphere, .cylinder, .cone, .plane, .torus, .capsule, .imported, .group
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for type in types {
            let entity = EntityData(name: "Test", type: type)
            let data = try encoder.encode(entity)
            let decoded = try decoder.decode(EntityData.self, from: data)
            #expect(decoded.type == type)
        }
    }
}
