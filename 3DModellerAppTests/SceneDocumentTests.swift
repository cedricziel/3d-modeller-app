@testable import _D_Modeller
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers

@Suite("SceneDocument Tests")
struct SceneDocumentTests {
    // MARK: - Initialization Tests

    @Test("Empty document initialization")
    func emptyDocumentInit() {
        let doc = SceneDocument()

        #expect(doc.sceneData.entities.isEmpty)
        #expect(doc.sceneData.metadata.name == "Untitled Scene")
    }

    // MARK: - SceneData Tests

    @Test("SceneData default values")
    func sceneDataDefaults() {
        let data = SceneData()

        #expect(data.entities.isEmpty)
        #expect(data.metadata.name == "Untitled Scene")
    }

    // MARK: - EntityData Tests

    @Test("EntityData initialization")
    func entityDataInit() {
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
    func entityDataWithTransform() {
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
    func transformDataDefaults() {
        let transform = TransformData()

        #expect(transform.position == .zero)
        #expect(transform.rotation == .zero)
        #expect(transform.scale == .one)
    }

    // MARK: - MaterialData Tests

    @Test("MaterialData default values")
    func materialDataDefaults() {
        let material = MaterialData()

        #expect(material.color.r == 0.8)
        #expect(material.color.g == 0.8)
        #expect(material.color.b == 0.8)
        #expect(material.metallic == 0.0)
        #expect(material.roughness == 0.5)
    }

    @Test("MaterialData custom color")
    func materialDataCustomColor() {
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
    func colorDataRGB() {
        let color = ColorData(r: 0.5, g: 0.6, b: 0.7)

        #expect(color.r == 0.5)
        #expect(color.g == 0.6)
        #expect(color.b == 0.7)
        #expect(color.a == 1.0)
    }

    @Test("ColorData RGBA initialization")
    func colorDataRGBA() {
        let color = ColorData(r: 0.5, g: 0.6, b: 0.7, a: 0.8)

        #expect(color.a == 0.8)
    }

    @Test("ColorData named color - red")
    func namedColorRed() {
        let color = ColorData(named: "red")

        #expect(color.r == 1.0)
        #expect(color.g == 0.0)
        #expect(color.b == 0.0)
    }

    @Test("ColorData named color - green")
    func namedColorGreen() {
        let color = ColorData(named: "green")

        #expect(color.r == 0.0)
        #expect(color.g == 1.0)
        #expect(color.b == 0.0)
    }

    @Test("ColorData named color - blue")
    func namedColorBlue() {
        let color = ColorData(named: "blue")

        #expect(color.r == 0.0)
        #expect(color.g == 0.0)
        #expect(color.b == 1.0)
    }

    @Test("ColorData named color case insensitive")
    func namedColorCaseInsensitive() {
        let color1 = ColorData(named: "RED")
        let color2 = ColorData(named: "Red")
        let color3 = ColorData(named: "red")

        #expect(color1.r == color2.r)
        #expect(color2.r == color3.r)
    }

    @Test("ColorData unknown named color returns default")
    func unknownNamedColor() {
        let color = ColorData(named: "unknowncolor")

        #expect(color.r == 0.8)
        #expect(color.g == 0.8)
        #expect(color.b == 0.8)
    }

    // MARK: - JSON Encoding/Decoding Tests

    @Test("SceneData JSON round-trip")
    func sceneDataJSONRoundTrip() throws {
        var original = SceneData()
        original.entities = [
            EntityData(name: "Box1", type: .box),
            EntityData(name: "Sphere1", type: .sphere),
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
    func entityDataJSONRoundTrip() throws {
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
    func entityTypeCodable() throws {
        let types: [EntityData.EntityType] = [
            .box, .sphere, .cylinder, .cone, .plane, .torus, .capsule, .imported, .group,
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

    // MARK: - FileDocument Tests

    @Test("SceneData JSON encoding creates valid data")
    func sceneDataJSONEncoding() throws {
        var sceneData = SceneData()
        sceneData.entities = [
            EntityData(name: "SavedBox", type: .box)
        ]
        sceneData.metadata.name = "Saved Scene"

        let encoder = JSONEncoder()
        let data = try encoder.encode(sceneData)

        #expect(!data.isEmpty)

        // Verify it's valid JSON by decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SceneData.self, from: data)
        #expect(decoded.entities.count == 1)
        #expect(decoded.metadata.name == "Saved Scene")
    }

    @Test("SceneData save and load round-trip")
    func saveLoadRoundTrip() throws {
        // Create original scene data
        var originalData = SceneData()
        originalData.entities = [
            EntityData(
                name: "TestCube",
                type: .box,
                transform: TransformData(position: [1, 2, 3]),
                material: MaterialData(color: ColorData(named: "red"))
            ),
            EntityData(name: "TestSphere", type: .sphere),
        ]
        originalData.metadata.name = "RoundTrip Test"

        // Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(originalData)

        // Decode
        let decoder = JSONDecoder()
        let loadedData = try decoder.decode(SceneData.self, from: data)

        // Verify
        #expect(loadedData.entities.count == 2)
        #expect(loadedData.metadata.name == "RoundTrip Test")
        #expect(loadedData.entities[0].name == "TestCube")
        #expect(loadedData.entities[0].transform.position == [1, 2, 3])
        #expect(loadedData.entities[1].type == .sphere)
    }

    @Test("SceneData decoding handles empty data")
    func emptyDataThrows() {
        let emptyData = Data()
        let decoder = JSONDecoder()

        #expect(throws: (any Error).self) {
            _ = try decoder.decode(SceneData.self, from: emptyData)
        }
    }

    @Test("SceneData decoding handles invalid JSON")
    func invalidJSONThrows() {
        let invalidJSON = "{ invalid json }".data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: (any Error).self) {
            _ = try decoder.decode(SceneData.self, from: invalidJSON)
        }
    }

    @Test("SceneData preserves entity IDs on round-trip")
    func entityIDsPreserved() throws {
        let entityId = UUID()

        var originalData = SceneData()
        originalData.entities = [
            EntityData(id: entityId, name: "IDTest", type: .cone)
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalData)

        let decoder = JSONDecoder()
        let loadedData = try decoder.decode(SceneData.self, from: data)

        #expect(loadedData.entities[0].id == entityId)
    }

    @Test("Saving writes the scene data the document currently holds")
    func snapshotReturnsCurrentSceneData() throws {
        let doc = SceneDocument()
        doc.sceneData.entities = [EntityData(name: "Saved", type: .cone)]

        let snapshot = try doc.snapshot(contentType: .sceneDocument)

        #expect(snapshot.entities.map(\.name) == ["Saved"])
    }

    @Test("SceneDocument content type")
    func contentTypes() {
        #expect(SceneDocument.readableContentTypes.contains(.sceneDocument))
        #expect(SceneDocument.writableContentTypes.contains(.sceneDocument))
    }
}
