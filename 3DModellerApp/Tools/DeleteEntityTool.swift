import Foundation
import SwiftUIAssistant

/// Tool for deleting entities from the scene
struct DeleteEntityTool: AssistantTool, @unchecked Sendable {
    let id = "delete_entity"
    let name = "delete_entity"
    let description = "Deletes an entity from the scene"

    let sceneManager: SceneManager

    var parameters: [ToolParameter] {
        [
            ToolParameter(
                name: "entityName",
                type: .string,
                description: "The name of the entity to delete",
                required: true
            )
        ]
    }

    func execute(arguments: [String: Any]) async throws -> ToolExecutionResult {
        guard let entityName = arguments["entityName"] as? String else {
            return ToolExecutionResult(
                success: false,
                message: "Missing required 'entityName' parameter",
                data: nil
            )
        }

        return await MainActor.run {
            let success = sceneManager.deleteEntity(named: entityName)

            if success {
                return ToolExecutionResult(
                    success: true,
                    message: "Deleted entity '\(entityName)'",
                    data: ["deletedEntityName": entityName]
                )
            } else {
                return ToolExecutionResult(
                    success: false,
                    message: "Entity '\(entityName)' not found",
                    data: nil
                )
            }
        }
    }
}
