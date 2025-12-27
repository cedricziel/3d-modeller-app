import Foundation
import SwiftUIAssistant

/// Tool for creating primitive 3D shapes
struct CreatePrimitiveTool: AssistantTool, @unchecked Sendable {
    let id = "create_primitive"
    let name = "create_primitive"
    let description = "Creates a 3D primitive shape in the scene"

    let sceneManager: SceneManager

    var parameters: [ToolParameter] {
        [
            ToolParameter(
                name: "type",
                type: .string,
                description: "The type of primitive to create",
                required: true,
                enumValues: ["box", "sphere", "cylinder", "cone", "plane", "torus"]
            ),
            ToolParameter(
                name: "name",
                type: .string,
                description: "Optional name for the entity",
                required: false
            ),
            ToolParameter(
                name: "position",
                type: .object,
                description: "Position as {x, y, z} in meters",
                required: false
            ),
            ToolParameter(
                name: "size",
                type: .number,
                description: "Size in meters (default 0.5)",
                required: false
            ),
            ToolParameter(
                name: "color",
                type: .string,
                description: "Color name (red, blue, green, etc.)",
                required: false
            )
        ]
    }

    func execute(arguments: [String: Any]) async throws -> ToolExecutionResult {
        // Parse arguments before MainActor
        guard let typeString = arguments["type"] as? String,
              let type = EntityData.EntityType(rawValue: typeString) else {
            return ToolExecutionResult(
                success: false,
                message: "Invalid or missing 'type' parameter",
                data: nil
            )
        }

        let name = arguments["name"] as? String
        let size = (arguments["size"] as? NSNumber)?.floatValue ?? 0.5
        let position = parsePosition(from: arguments["position"] as? [String: Any])

        var color = ColorData(r: 0.8, g: 0.8, b: 0.8)
        if let colorName = arguments["color"] as? String {
            color = ColorData(named: colorName)
        }

        // Execute on MainActor
        return await MainActor.run {
            let entity = sceneManager.createPrimitive(
                type: type,
                name: name,
                position: position,
                size: size,
                color: color
            )
            sceneManager.select(id: entity.id)

            let posStr = "(\(position.x), \(position.y), \(position.z))"
            return ToolExecutionResult(
                success: true,
                message: "Created \(type.rawValue) '\(entity.name)' at \(posStr)",
                data: [
                    "entityId": entity.id.uuidString,
                    "entityName": entity.name,
                    "type": type.rawValue
                ]
            )
        }
    }

    private func parsePosition(from dict: [String: Any]?) -> SIMD3<Float> {
        guard let dict = dict else { return .zero }
        let posX = (dict["x"] as? NSNumber)?.floatValue ?? 0
        let posY = (dict["y"] as? NSNumber)?.floatValue ?? 0
        let posZ = (dict["z"] as? NSNumber)?.floatValue ?? 0
        return [posX, posY, posZ]
    }
}
