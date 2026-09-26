import SwiftUI
import Synchronization
import UniformTypeIdentifiers

/// Document type for 3D scenes. A reference document, so SwiftUI tracks unsaved changes through
/// the window's undo manager, where `SceneManager` records its edits.
final class SceneDocument: ReferenceFileDocument {
    private let storage: Mutex<SceneData>

    var sceneData: SceneData {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    static var readableContentTypes: [UTType] { [.sceneDocument] }
    static var writableContentTypes: [UTType] { [.sceneDocument] }

    init(sceneData: SceneData = SceneData()) {
        storage = Mutex(sceneData)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        storage = Mutex(try JSONDecoder().decode(SceneData.self, from: data))
    }

    func snapshot(contentType: UTType) throws -> SceneData {
        sceneData
    }

    func fileWrapper(snapshot: SceneData, configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return FileWrapper(regularFileWithContents: try encoder.encode(snapshot))
    }
}

// MARK: - UTType Extension

extension UTType {
    static var sceneDocument: UTType {
        UTType(exportedAs: "com.example.3dmodeller.scene")
    }
}

// MARK: - Scene Data

/// Serializable scene data structure
struct SceneData: Codable {
    var entities: [EntityData] = []
    var metadata: SceneMetadata = SceneMetadata()

    struct SceneMetadata: Codable {
        var name: String = "Untitled Scene"
        var createdAt: Date = Date()
        var modifiedAt: Date = Date()
    }
}

/// Serializable entity data
struct EntityData: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: EntityType
    var transform: TransformData
    var material: MaterialData
    var parentId: UUID?
    var isVisible: Bool
    var solid: SolidRecipe?

    enum EntityType: String, Codable {
        case box
        case sphere
        case cylinder
        case cone
        case plane
        case torus
        case capsule
        case imported
        case group
        case solid
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: EntityType,
        transform: TransformData = TransformData(),
        material: MaterialData = MaterialData(),
        parentId: UUID? = nil,
        isVisible: Bool = true,
        solid: SolidRecipe? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.transform = transform
        self.material = material
        self.parentId = parentId
        self.isVisible = isVisible
        self.solid = solid
    }
}

struct SolidRecipe: Codable, Equatable {
    var width: Double
    var height: Double
    var depth: Double
    var filletRadius: Double?
}

/// Serializable transform data
struct TransformData: Codable {
    var position: SIMD3<Float>
    var rotation: SIMD3<Float>  // Euler angles in radians
    var scale: SIMD3<Float>

    init(
        position: SIMD3<Float> = .zero,
        rotation: SIMD3<Float> = .zero,
        scale: SIMD3<Float> = .one
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

/// Serializable material data
struct MaterialData: Codable {
    var color: ColorData
    var metallic: Float
    var roughness: Float

    init(
        color: ColorData = ColorData(r: 0.8, g: 0.8, b: 0.8, a: 1.0),
        metallic: Float = 0.0,
        roughness: Float = 0.5
    ) {
        self.color = color
        self.metallic = metallic
        self.roughness = roughness
    }
}

/// Serializable color data
struct ColorData: Codable, Hashable {
    // swiftlint:disable identifier_name
    var r: Float
    var g: Float
    var b: Float
    var a: Float
    // swiftlint:enable identifier_name

    init(r: Float, g: Float, b: Float, a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Named color lookup table
    private static let namedColors: [String: ColorData] = [
        "red": ColorData(r: 1, g: 0, b: 0),
        "green": ColorData(r: 0, g: 1, b: 0),
        "blue": ColorData(r: 0, g: 0, b: 1),
        "yellow": ColorData(r: 1, g: 1, b: 0),
        "orange": ColorData(r: 1, g: 0.5, b: 0),
        "purple": ColorData(r: 0.5, g: 0, b: 0.5),
        "cyan": ColorData(r: 0, g: 1, b: 1),
        "magenta": ColorData(r: 1, g: 0, b: 1),
        "white": ColorData(r: 1, g: 1, b: 1),
        "black": ColorData(r: 0, g: 0, b: 0),
        "gray": ColorData(r: 0.5, g: 0.5, b: 0.5),
        "grey": ColorData(r: 0.5, g: 0.5, b: 0.5),
    ]

    /// Named color initializer
    init(named: String) {
        self = Self.namedColors[named.lowercased()] ?? ColorData(r: 0.8, g: 0.8, b: 0.8)
    }
}
