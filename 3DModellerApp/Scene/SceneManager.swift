import CADKernel
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

    /// Name and dates of the loaded document, written back on save
    private var metadata = SceneData.SceneMetadata()

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

        let data = EntityData(
            name: name ?? generateName(for: type),
            type: type,
            transform: TransformData(position: position),
            material: MaterialData(color: color)
        )
        let cadEntity = addEntity(from: data, size: size)
        sceneDidChange()

        return cadEntity
    }

    /// Builds an entity from its saved data without recording an undo step
    @discardableResult
    private func addEntity(from data: EntityData, size: Float = 0.5) -> CADEntity {
        let mesh: MeshResource
        switch data.type {
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
        return addEntity(from: data, mesh: mesh)
    }

    @discardableResult
    private func addEntity(from data: EntityData, mesh: MeshResource) -> CADEntity {
        let modelEntity = ModelEntity(mesh: mesh, materials: [Self.makeMaterial(data.material)])
        modelEntity.name = data.name
        modelEntity.position = data.transform.position
        modelEntity.orientation = Self.orientation(fromEuler: data.transform.rotation)
        modelEntity.scale = data.transform.scale
        modelEntity.isEnabled = data.isVisible

        rootEntity.addChild(modelEntity)

        let cadEntity = CADEntity(
            id: data.id,
            name: data.name,
            type: data.type,
            entity: modelEntity,
            material: data.material,
            parentId: data.parentId,
            solid: data.solid
        )
        entities[data.id] = cadEntity
        return cadEntity
    }

    func createSolid(
        recipe: SolidRecipe,
        name: String? = nil,
        position: SIMD3<Float> = .zero,
        color: ColorData = ColorData(r: 0.8, g: 0.8, b: 0.8)
    ) throws -> CADEntity {
        let mesh = try Self.buildMesh(for: recipe)

        saveUndoState()

        let data = EntityData(
            name: name ?? generateName(for: .solid),
            type: .solid,
            transform: TransformData(position: position),
            material: MaterialData(color: color),
            solid: recipe
        )
        let cadEntity = addEntity(from: data, mesh: mesh)
        sceneDidChange()

        return cadEntity
    }

    private static func buildMesh(for recipe: SolidRecipe) throws -> MeshResource {
        var solid = try Kernel.extrudeRectangle(width: recipe.width, height: recipe.height, depth: recipe.depth)
        if let radius = recipe.filletRadius {
            solid = try Kernel.fillet(solid, edges: .parallel(to: SIMD3(0, 0, 1)), radius: radius)
        }
        return try MeshResource.generate(from: [Kernel.tessellate(solid).meshDescriptor])
    }

    private static func makeMaterial(_ data: MaterialData) -> SimpleMaterial {
        var material = SimpleMaterial()
        #if os(macOS)
            material.color = .init(
                tint: NSColor(
                    red: CGFloat(data.color.r),
                    green: CGFloat(data.color.g),
                    blue: CGFloat(data.color.b),
                    alpha: CGFloat(data.color.a)
                ))
        #else
            material.color = .init(
                tint: UIColor(
                    red: CGFloat(data.color.r),
                    green: CGFloat(data.color.g),
                    blue: CGFloat(data.color.b),
                    alpha: CGFloat(data.color.a)
                ))
        #endif
        material.metallic = .init(floatLiteral: data.metallic)
        material.roughness = .init(floatLiteral: data.roughness)
        return material
    }

    /// Euler angles in radians, applied as X * Y * Z
    private static func orientation(fromEuler angles: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: angles.x, axis: [1, 0, 0])
            * simd_quatf(angle: angles.y, axis: [0, 1, 0])
            * simd_quatf(angle: angles.z, axis: [0, 0, 1])
    }

    /// Inverse of `orientation(fromEuler:)`
    private static func eulerAngles(from orientation: simd_quatf) -> SIMD3<Float> {
        let m = simd_float3x3(orientation)
        let sinY = min(max(m[2][0], -1), 1)
        let y = asin(sinY)
        if abs(sinY) < 0.9999 {
            return [atan2(-m[2][1], m[2][2]), y, atan2(-m[1][0], m[0][0])]
        }
        return [atan2(m[1][2], m[1][1]), y, 0]
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
            cadEntity.entity.orientation = Self.orientation(fromEuler: rot * (Float.pi / 180))
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

        if let color = color {
            cadEntity.material.color = color
        }
        if let metallic = metallic {
            cadEntity.material.metallic = metallic
        }
        if let roughness = roughness {
            cadEntity.material.roughness = roughness
        }

        modelEntity.model?.materials = [Self.makeMaterial(cadEntity.material)]
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

        let position = original.entity.position + SIMD3<Float>(0.5, 0, 0.5)
        if let recipe = original.solid {
            return try? createSolid(recipe: recipe, name: name, position: position, color: original.material.color)
        }
        return createPrimitive(
            type: original.type,
            name: name,
            position: position,
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
        updateStatistics()
    }

    private func updateStatistics() {
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
        undoStack.append(SceneSnapshot(entities: entities))
        redoStack.removeAll()

        // Limit undo stack size
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(SceneSnapshot(entities: entities))
        restoreSnapshot(snapshot)
        sceneDidChange()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(SceneSnapshot(entities: entities))
        restoreSnapshot(snapshot)
        sceneDidChange()
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
                material: saved.material,
                parentId: saved.parentId,
                solid: saved.solid
            )
        }

        if let selected = selectedEntityId, entities[selected] == nil {
            selectedEntityId = nil
        }
    }

    // MARK: - Serialization

    private func entityData(for entity: CADEntity) -> EntityData {
        EntityData(
            id: entity.id,
            name: entity.name,
            type: entity.type,
            transform: TransformData(
                position: entity.entity.position,
                rotation: Self.eulerAngles(from: entity.entity.orientation),
                scale: entity.entity.scale
            ),
            material: entity.material,
            parentId: entity.parentId,
            isVisible: entity.entity.isEnabled,
            solid: entity.solid
        )
    }

    func toSceneData() -> SceneData {
        var metadata = self.metadata
        metadata.modifiedAt = Date()
        return SceneData(entities: entities.values.map(entityData(for:)), metadata: metadata)
    }

    /// Replaces the scene with `data`. Not an edit: the undo history is cleared and `revision` is unchanged.
    func loadSceneData(_ data: SceneData) {
        for entity in entities.values {
            entity.entity.removeFromParent()
        }
        entities.removeAll()
        selectedEntityId = nil
        for entityData in data.entities {
            if let recipe = entityData.solid {
                if let mesh = try? Self.buildMesh(for: recipe) {
                    addEntity(from: entityData, mesh: mesh)
                }
            } else {
                addEntity(from: entityData)
            }
        }
        metadata = data.metadata
        entityCounters.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        updateStatistics()
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
    var parentId: UUID?
    let solid: SolidRecipe?

    init(
        id: UUID,
        name: String,
        type: EntityData.EntityType,
        entity: Entity,
        material: MaterialData,
        parentId: UUID? = nil,
        solid: SolidRecipe? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.entity = entity
        self.material = material
        self.parentId = parentId
        self.solid = solid
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
                material: live.material,
                parentId: live.parentId,
                solid: live.solid
            )
        }
    }
}
