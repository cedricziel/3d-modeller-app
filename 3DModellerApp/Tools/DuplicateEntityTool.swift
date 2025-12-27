import Foundation
import SwiftUIAssistant

/// Tool for duplicating entities
struct DuplicateEntityTool: AssistantTool, @unchecked Sendable {
    let id = "duplicate_entity"
    let name = "duplicate_entity"
    let description = "Creates a copy of an existing entity"

    let sceneManager: SceneManager

    var parameters: [ToolParameter] {
        [
            ToolParameter(
                name: "entityName",
                type: .string,
                description: "The name of the entity to duplicate",
                required: true
            ),
            ToolParameter(
                name: "newName",
                type: .string,
                description: "Optional name for the duplicate",
                required: false
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

        let newName = arguments["newName"] as? String

        return await MainActor.run {
            guard let entity = sceneManager.entity(named: entityName) else {
                return ToolExecutionResult(
                    success: false,
                    message: "Entity '\(entityName)' not found",
                    data: nil
                )
            }

            guard let duplicate = sceneManager.duplicateEntity(id: entity.id, newName: newName) else {
                return ToolExecutionResult(
                    success: false,
                    message: "Failed to duplicate entity '\(entityName)'",
                    data: nil
                )
            }

            sceneManager.select(id: duplicate.id)

            return ToolExecutionResult(
                success: true,
                message: "Duplicated '\(entityName)' as '\(duplicate.name)'",
                data: [
                    "originalEntityName": entityName,
                    "newEntityId": duplicate.id.uuidString,
                    "newEntityName": duplicate.name
                ]
            )
        }
    }
}
