import Foundation
import SwiftUIAssistant

/// Tool for setting material properties on entities
struct SetMaterialTool: AssistantTool, @unchecked Sendable {
    let id = "set_material"
    let name = "set_material"
    let description = "Sets material properties (color, metallic, roughness) on an entity"

    let sceneManager: SceneManager

    var parameters: [ToolParameter] {
        [
            ToolParameter(
                name: "entityName",
                type: .string,
                description: "The name of the entity to modify",
                required: true
            ),
            ToolParameter(
                name: "color",
                type: .string,
                description: "Color name (red, blue, green, etc.)",
                required: false
            ),
            ToolParameter(
                name: "metallic",
                type: .number,
                description: "Metallic value 0.0 to 1.0",
                required: false
            ),
            ToolParameter(
                name: "roughness",
                type: .number,
                description: "Roughness value 0.0 to 1.0",
                required: false
            )
        ]
    }

    func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        guard let entityName = arguments["entityName"]?.stringValue else {
            return ToolExecutionResult(
                success: false,
                message: "Missing required 'entityName' parameter",
                data: nil
            )
        }

        var color: ColorData?
        if let colorName = arguments["color"]?.stringValue {
            color = ColorData(named: colorName)
        }

        let metallic = arguments["metallic"]?.floatValue
        let roughness = arguments["roughness"]?.floatValue

        return await MainActor.run {
            guard let entity = sceneManager.entity(named: entityName) else {
                return ToolExecutionResult(
                    success: false,
                    message: "Entity '\(entityName)' not found",
                    data: nil
                )
            }

            let success = sceneManager.setMaterial(
                id: entity.id,
                color: color,
                metallic: metallic,
                roughness: roughness
            )

            if success {
                var changes: [String] = []
                if color != nil { changes.append("color") }
                if metallic != nil { changes.append("metallic") }
                if roughness != nil { changes.append("roughness") }

                return ToolExecutionResult(
                    success: true,
                    message: "Updated material on '\(entityName)': \(changes.joined(separator: ", "))",
                    data: ["entityName": .string(entityName), "entityId": .string(entity.id.uuidString)]
                )
            } else {
                return ToolExecutionResult(
                    success: false,
                    message: "Failed to update material on '\(entityName)'",
                    data: nil
                )
            }
        }
    }
}
