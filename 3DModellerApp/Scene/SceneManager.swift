import SwiftUI
import RealityKit
import Combine

/// Manages the RealityKit scene and entity operations
@MainActor
final class SceneManager: ObservableObject {
    // MARK: - Published State

    /// All entities in the scene (by ID)
    @Published private(set) var entities: [UUID: CADEntity] = [:]

    /// Currently selected entity
    @Published var selectedEntityId: UUID?

    /// Scene statistics
    @Published private(set) var statistics: SceneStatistics = SceneStatistics()

    /// Bumped on every edit, since entities are mutated in place and `entities` alone doesn't publish those
    @Published private(set) var revision = 0

    // MARK: - RealityKit

    /// The root entity for the scene
    let rootEntity: Entity

    /// Ground grid entity
    private var gridEntity: Entity?

    /// Entity name counter for auto-naming
    private var entityCounters: [EntityData.EntityType: Int] = [:]

    // MARK: - Undo/Redo

    private var undoStack: [SceneSnapshot] = []
    private var redoStack: [SceneSnapshot] = []

    // MARK: - Initialization

    init() {
        self.rootEntity = Entity()
        setupScene()
    }

    private func setupScene() {
        // Add ground grid
        let grid = createGridEntity()
        rootEntity.addChild(grid)
        self.gridEntity = grid

        // Add ambient light
        let light = Entity()
        light.components[PointLightComponent.self] = PointLightComponent(
            color: .white,
            intensity: 10000
        )
        light.position = [2, 3, 2]
        rootEntity.addChild(light)
    }

    private func createGridEntity() -> Entity {
        let gridEntity = Entity()

        // Create grid lines using simple mesh
        let gridSize: Float = 10
        let gridSpacing: Float = 0.5
        let gridMaterial = SimpleMaterial(color: .gray.withAlphaComponent(0.3), isMetallic: false)

        for i in stride(from: -gridSize, through: gridSize, by: gridSpacing) {
            // X-axis lines
            let xLine = ModelEntity(
                mesh: .generateBox(width: gridSize * 2, height: 0.005, depth: 0.005),
                materials: [gridMaterial]
            )
            xLine.position = [0, 0, i]
            gridEntity.addChild(xLine)

            // Z-axis lines
            let zLine = ModelEntity(
                mesh: .generateBox(width: 0.005, height: 0.005, depth: gridSize * 2),
                materials: [gridMaterial]
            )
            zLine.position = [i, 0, 0]
            gridEntity.addChild(zLine)
        }

        return gridEntity
    }

    // MARK: - Entity Management

    /// Get the currently selected entity
    var selectedEntity: CADEntity? {
        guard let id = selectedEntityId else { return nil }
        return entities[id]
    }

    /// Create a primitive shape
    func createPrimitive(
        type: EntityData.EntityType,
        name: String? = nil,
        position: SIMD3<Float> = .zero,
        size: Float = 0.5,
        color: ColorData = ColorData(r: 0.8, g: 0.8, b: 0.8)
    ) -> CADEntity {
        saveUndoState()

        let entityName = name ?? generateName(for: type)
        let id = UUID()

        // Create RealityKit mesh
        let mesh: MeshResource
        switch type {
        case .box:
            mesh = .generateBox(size: size)
        case .sphere:
            mesh = .generateSphere(radius: size / 2)
        case .cylinder:
            mesh = .generateCylinder(height: size, radius: size / 3)
        case .cone:
            mesh = .generateCone(height: size, radius: size / 3)
        case .plane:
            mesh = .generatePlane(width: size, depth: size)
        case .torus:
            // RealityKit doesn't have built-in torus, use a flattened sphere as approximation
            mesh = .generateSphere(radius: size / 2)
        case .capsule:
            // Use cylinder as approximation for capsule
            mesh = .generateCylinder(height: size, radius: size / 4)
        default:
            mesh = .generateBox(size: size)
        }

        // Create material
        var material = SimpleMaterial()
        #if os(macOS)
            material.color = .init(
                tint: NSColor(
                    red: CGFloat(color.r),
                    green: CGFloat(color.g),
                    blue: CGFloat(color.b),
                    alpha: CGFloat(color.a)
                ))
        #else
            material.color = .init(
                tint: UIColor(
                    red: CGFloat(color.r),
                    green: CGFloat(color.g),
                    blue: CGFloat(color.b),
                    alpha: CGFloat(color.a)
                ))
        #endif

        // Create model entity
        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
        modelEntity.position = position
        modelEntity.name = entityName

        // Add to scene
        rootEntity.addChild(modelEntity)

        // Create CAD entity wrapper
        let cadEntity = CADEntity(
            id: id,
            name: entityName,
            type: type,
            entity: modelEntity,
            material: MaterialData(color: color)
        )

        entities[id] = cadEntity
        sceneDidChange()

        return cadEntity
    }

    /// Delete an entity by ID
    func deleteEntity(id: UUID) -> Bool {
        guard let cadEntity = entities[id] else { return false }

        saveUndoState()

        cadEntity.entity.removeFromParent()
        entities.removeValue(forKey: id)

        if selectedEntityId == id {
            selectedEntityId = nil
        }

        sceneDidChange()
        return true
    }

    /// Delete an entity by name
    func deleteEntity(named name: String) -> Bool {
        guard let entity = entities.values.first(where: { $0.name == name }) else {
            return false
        }
        return deleteEntity(id: entity.id)
    }

    /// Transform an entity
    func transformEntity(
        id: UUID,
        position: SIMD3<Float>? = nil,
        rotation: SIMD3<Float>? = nil,
        scale: SIMD3<Float>? = nil
    ) -> Bool {
        guard let cadEntity = entities[id] else { return false }

        saveUndoState()

        if let pos = position {
            cadEntity.entity.position = pos
        }

        if let rot = rotation {
            // Convert Euler angles (degrees) to quaternion
            let radians = rot * (Float.pi / 180)
            cadEntity.entity.orientation =
                simd_quatf(
                    angle: radians.x, axis: [1, 0, 0]
                )
                * simd_quatf(
                    angle: radians.y, axis: [0, 1, 0]
                )
                * simd_quatf(
                    angle: radians.z, axis: [0, 0, 1]
                )
        }

        if let scl = scale {
            cadEntity.entity.scale = scl
        }

        sceneDidChange()
        return true
    }

    /// Transform an entity by name
    func transformEntity(
        named name: String,
        position: SIMD3<Float>? = nil,
        rotation: SIMD3<Float>? = nil,
        scale: SIMD3<Float>? = nil
    ) -> Bool {
        guard let entity = entities.values.first(where: { $0.name == name }) else {
            return false
        }
        return transformEntity(id: entity.id, position: position, rotation: rotation, scale: scale)
    }

    /// Set material properties on an entity
    func setMaterial(
        id: UUID,
        color: ColorData? = nil,
        metallic: Float? = nil,
        roughness: Float? = nil
    ) -> Bool {
        guard let cadEntity = entities[id],
            let modelEntity = cadEntity.entity as? ModelEntity
        else {
            return false
        }

        saveUndoState()

        var material = SimpleMaterial()

        if let color = color {
            #if os(macOS)
                material.color = .init(
                    tint: NSColor(
                        red: CGFloat(color.r),
                        green: CGFloat(color.g),
                        blue: CGFloat(color.b),
                        alpha: CGFloat(color.a)
                    ))
            #else
                material.color = .init(
                    tint: UIColor(
                        red: CGFloat(color.r),
                        green: CGFloat(color.g),
                        blue: CGFloat(color.b),
                        alpha: CGFloat(color.a)
                    ))
            #endif
            cadEntity.material.color = color
        }

        if let metallic = metallic {
            material.metallic = .init(floatLiteral: metallic)
            cadEntity.material.metallic = metallic
        }

        if let roughness = roughness {
            material.roughness = .init(floatLiteral: roughness)
            cadEntity.material.roughness = roughness
        }

        modelEntity.model?.materials = [material]
        sceneDidChange()
        return true
    }

    /// Set material by entity name
    func setMaterial(
        named name: String,
        color: ColorData? = nil,
        metallic: Float? = nil,
        roughness: Float? = nil
    ) -> Bool {
        guard let entity = entities.values.first(where: { $0.name == name }) else {
            return false
        }
        return setMaterial(id: entity.id, color: color, metallic: metallic, roughness: roughness)
    }

    /// Duplicate an entity
    func duplicateEntity(id: UUID, newName: String? = nil) -> CADEntity? {
        guard let original = entities[id] else { return nil }

        let name = newName ?? "\(original.name)_copy"

        return createPrimitive(
            type: original.type,
            name: name,
            position: original.entity.position + SIMD3<Float>(0.5, 0, 0.5),
            color: original.material.color
        )
    }

    /// Get entity by name
    func entity(named name: String) -> CADEntity? {
        entities.values.first { $0.name == name }
    }

    // MARK: - Selection

    func select(id: UUID?) {
        selectedEntityId = id
    }

    func select(named name: String) {
        if let entity = entities.values.first(where: { $0.name == name }) {
            selectedEntityId = entity.id
        }
    }

    // MARK: - Naming

    private func generateName(for type: EntityData.EntityType) -> String {
        let count = (entityCounters[type] ?? 0) + 1
        entityCounters[type] = count
        return "\(type.rawValue.capitalized)_\(count)"
    }

    // MARK: - Statistics

    private func sceneDidChange() {
        revision += 1
        statistics = SceneStatistics(
            entityCount: entities.count,
            triangleCount: calculateTriangleCount(),
            materialCount: countUniqueMaterials()
        )
    }

    private func countUniqueMaterials() -> Int {
        var uniqueMaterials: Set<Int> = []
        for entity in entities.values {
            let mat = entity.material
            var hasher = Hasher()
            hasher.combine(mat.color.r)
            hasher.combine(mat.color.g)
            hasher.combine(mat.color.b)
            hasher.combine(mat.metallic)
            hasher.combine(mat.roughness)
            uniqueMaterials.insert(hasher.finalize())
        }
        return uniqueMaterials.count
    }

    private func calculateTriangleCount() -> Int {
        // Approximate triangle count based on primitive types
        var count = 0
        for entity in entities.values {
            switch entity.type {
            case .box: count += 12
            case .sphere: count += 960  // Approximation
            case .cylinder: count += 100
            case .cone: count += 50
            case .plane: count += 2
            case .torus: count += 576
            case .capsule: count += 500
            default: count += 12
            }
        }
        return count
    }

    // MARK: - Undo/Redo

    private func saveUndoState() {
        let snapshot = SceneSnapshot(entities: entities)
        undoStack.append(snapshot)
        redoStack.removeAll()

        // Limit undo stack size
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        let currentSnapshot = SceneSnapshot(entities: entities)
        redoStack.append(currentSnapshot)
        restoreSnapshot(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        let currentSnapshot = SceneSnapshot(entities: entities)
        undoStack.append(currentSnapshot)
        restoreSnapshot(snapshot)
    }

    private func restoreSnapshot(_ snapshot: SceneSnapshot) {
        for entity in entities.values {
            entity.entity.removeFromParent()
        }

        entities = snapshot.entities.mapValues { saved in
            let entity = saved.entity.clone(recursive: true)
            rootEntity.addChild(entity)
            return CADEntity(
                id: saved.id,
                name: saved.name,
                type: saved.type,
                entity: entity,
                material: saved.material
            )
        }

        if let selected = selectedEntityId, entities[selected] == nil {
            selectedEntityId = nil
        }

        sceneDidChange()
    }

    // MARK: - Serialization

    func toSceneData() -> SceneData {
        var data = SceneData()
        data.entities = entities.values.map { entity in
            EntityData(
                id: entity.id,
                name: entity.name,
                type: entity.type,
                transform: TransformData(
                    position: entity.entity.position,
                    rotation: .zero,  // TODO: Extract Euler from quaternion
                    scale: entity.entity.scale
                ),
                material: entity.material
            )
        }
        return data
    }

    func loadSceneData(_ data: SceneData) {
        // Clear current scene
        for entity in entities.values {
            entity.entity.removeFromParent()
        }
        entities.removeAll()
        entityCounters.removeAll()

        // Load entities
        for entityData in data.entities {
            _ = createPrimitive(
                type: entityData.type,
                name: entityData.name,
                position: entityData.transform.position,
                color: entityData.material.color
            )
        }
    }
}

// MARK: - Supporting Types

/// Wrapper for a CAD entity
class CADEntity {
    let id: UUID
    var name: String
    let type: EntityData.EntityType
    let entity: Entity
    var material: MaterialData

    init(
        id: UUID,
        name: String,
        type: EntityData.EntityType,
        entity: Entity,
        material: MaterialData
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.entity = entity
        self.material = material
    }
}

/// Scene statistics
struct SceneStatistics {
    var entityCount: Int = 0
    var triangleCount: Int = 0
    var materialCount: Int = 0
}

/// Snapshot for undo/redo
struct SceneSnapshot {
    let entities: [UUID: CADEntity]

    init(entities: [UUID: CADEntity]) {
        self.entities = entities.mapValues { live in
            CADEntity(
                id: live.id,
                name: live.name,
                type: live.type,
                entity: live.entity.clone(recursive: true),
                material: live.material
            )
        }
    }
}
