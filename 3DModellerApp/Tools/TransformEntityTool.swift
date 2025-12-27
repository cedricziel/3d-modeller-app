import Foundation
import SwiftUIAssistant

/// Tool for transforming entities (position, rotation, scale)
struct TransformEntityTool: AssistantTool, @unchecked Sendable {
    let id = "transform_entity"
    let name = "transform_entity"
    let description = "Transforms an entity by changing position, rotation, or scale"

    let sceneManager: SceneManager

    var parameters: [ToolParameter] {
        [
            ToolParameter(
                name: "entityName",
                type: .string,
                description: "The name of the entity to transform",
                required: true
            ),
            ToolParameter(
                name: "position",
                type: .object,
                description: "New position as {x, y, z} in meters",
                required: false
            ),
            ToolParameter(
                name: "rotation",
                type: .object,
                description: "New rotation as {x, y, z} in degrees",
                required: false
            ),
            ToolParameter(
                name: "scale",
                type: .object,
                description: "New scale as {x, y, z} or uniform number",
                required: false
            )
        ]
    }

    func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        guard let entityName = arguments["entityName"]?.stringValue else {
            return ToolExecutionResult(success: false, message: "Missing 'entityName'", data: nil)
        }

        let position = parseVector(from: arguments["position"])
        let rotation = parseVector(from: arguments["rotation"])
        let scale = parseScale(from: arguments["scale"])

        return await MainActor.run {
            guard let entity = sceneManager.entity(named: entityName) else {
                return ToolExecutionResult(
                    success: false,
                    message: "Entity '\(entityName)' not found",
                    data: nil
                )
            }

            let success = sceneManager.transformEntity(
                id: entity.id,
                position: position,
                rotation: rotation,
                scale: scale
            )

            guard success else {
                return ToolExecutionResult(
                    success: false,
                    message: "Failed to transform '\(entityName)'",
                    data: nil
                )
            }

            var changes: [String] = []
            if position != nil { changes.append("position") }
            if rotation != nil { changes.append("rotation") }
            if scale != nil { changes.append("scale") }

            return ToolExecutionResult(
                success: true,
                message: "Transformed '\(entityName)': \(changes.joined(separator: ", "))",
                data: ["entityName": .string(entityName), "entityId": .string(entity.id.uuidString)]
            )
        }
    }

    private func parseVector(from value: JSONValue?) -> SIMD3<Float>? {
        guard let dict = value?.objectValue else { return nil }
        let vecX = dict["x"]?.floatValue ?? 0
        let vecY = dict["y"]?.floatValue ?? 0
        let vecZ = dict["z"]?.floatValue ?? 0
        return [vecX, vecY, vecZ]
    }

    private func parseScale(from value: JSONValue?) -> SIMD3<Float>? {
        if let dict = value?.objectValue {
            let scaleX = dict["x"]?.floatValue ?? 1
            let scaleY = dict["y"]?.floatValue ?? 1
            let scaleZ = dict["z"]?.floatValue ?? 1
            return [scaleX, scaleY, scaleZ]
        } else if let uniform = value?.floatValue {
            return [uniform, uniform, uniform]
        }
        return nil
    }
}
