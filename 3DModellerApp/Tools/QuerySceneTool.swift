import Foundation
import SwiftUIAssistant

/// Tool for querying scene information
struct QuerySceneTool: AssistantTool, @unchecked Sendable {
    let id = "query_scene"
    let name = "query_scene"
    let description = "Queries information about entities in the scene"

    let sceneManager: SceneManager

    var parameters: [ToolParameter] {
        [
            ToolParameter(
                name: "filter",
                type: .string,
                description: "Optional name pattern to filter entities",
                required: false
            ),
            ToolParameter(
                name: "type",
                type: .string,
                description: "Optional entity type filter",
                required: false,
                enumValues: ["box", "sphere", "cylinder", "cone", "plane", "torus"]
            )
        ]
    }

    func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        let filter = arguments["filter"]?.stringValue
        let typeFilter = arguments["type"]?.stringValue

        return await MainActor.run {
            var entities = Array(sceneManager.entities.values)

            // Apply name filter
            if let filter = filter, !filter.isEmpty {
                entities = entities.filter { $0.name.localizedCaseInsensitiveContains(filter) }
            }

            // Apply type filter
            if let typeFilter = typeFilter,
               let entityType = EntityData.EntityType(rawValue: typeFilter) {
                entities = entities.filter { $0.type == entityType }
            }

            let entityInfos: [JSONValue] = entities.map { entity in
                .object([
                    "id": .string(entity.id.uuidString),
                    "name": .string(entity.name),
                    "type": .string(entity.type.rawValue),
                    "position": .object([
                        "x": .number(Double(entity.entity.position.x)),
                        "y": .number(Double(entity.entity.position.y)),
                        "z": .number(Double(entity.entity.position.z))
                    ]),
                    "isSelected": .bool(entity.id == sceneManager.selectedEntityId)
                ])
            }

            let stats = sceneManager.statistics
            let message: String
            if entities.isEmpty {
                message = filter != nil || typeFilter != nil
                    ? "No entities match the filter"
                    : "The scene is empty"
            } else {
                let names = entities.map { $0.name }.joined(separator: ", ")
                message = "Found \(entities.count) entities: \(names)"
            }

            return ToolExecutionResult(
                success: true,
                message: message,
                data: [
                    "entities": .array(entityInfos),
                    "statistics": .object([
                        "totalEntities": .integer(stats.entityCount),
                        "triangleCount": .integer(stats.triangleCount)
                    ])
                ]
            )
        }
    }
}
