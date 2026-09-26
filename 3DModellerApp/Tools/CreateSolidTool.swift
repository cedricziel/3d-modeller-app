import Foundation
import SwiftUIAssistant

struct CreateSolidTool: AssistantTool, @unchecked Sendable {
    let id = "create_solid"
    let name = "create_solid"
    let description = """
        Creates a solid block with exact CAD geometry: a width × height rectangle extruded upward by depth. \
        Optionally rounds the four vertical edges with fillet_radius, which must be less than half of \
        the smaller of width and height.
        """

    let sceneManager: SceneManager

    var parameters: [ToolParameter] {
        [
            ToolParameter(name: "width", type: .number, description: "Size along X in meters", required: true),
            ToolParameter(
                name: "height", type: .number, description: "Size along Z (depth into the scene) in meters",
                required: true),
            ToolParameter(
                name: "depth", type: .number, description: "Extrusion distance upward along Y in meters",
                required: true),
            ToolParameter(
                name: "fillet_radius", type: .number, description: "Radius for rounding the vertical edges, in meters",
                required: false),
            ToolParameter(name: "name", type: .string, description: "Optional name for the entity", required: false),
            ToolParameter(
                name: "position", type: .object, description: "Position as {x, y, z} in meters", required: false),
            ToolParameter(
                name: "color", type: .string, description: "Color name (red, blue, green, etc.)", required: false),
        ]
    }

    func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        var invalid = ["width", "height", "depth"].filter { arguments[$0]?.doubleValue == nil }
        if let fillet = arguments["fillet_radius"], fillet != .null, fillet.doubleValue == nil {
            invalid.append("fillet_radius")
        }
        guard invalid.isEmpty,
            let width = arguments["width"]?.doubleValue,
            let height = arguments["height"]?.doubleValue,
            let depth = arguments["depth"]?.doubleValue
        else {
            return ToolExecutionResult(
                success: false,
                message: "Missing or non-numeric: \(invalid.joined(separator: ", "))",
                data: nil
            )
        }

        let recipe = SolidRecipe(
            width: width,
            height: height,
            depth: depth,
            filletRadius: arguments["fillet_radius"]?.doubleValue
        )
        let name = arguments["name"]?.stringValue
        let position = parsePosition(from: arguments["position"]?.objectValue)
        let color = arguments["color"]?.stringValue.map { ColorData(named: $0) } ?? ColorData(r: 0.8, g: 0.8, b: 0.8)

        return await MainActor.run {
            do {
                let entity = try sceneManager.createSolid(recipe: recipe, name: name, position: position, color: color)
                sceneManager.select(id: entity.id)
                return ToolExecutionResult(
                    success: true,
                    message: "Created solid '\(entity.name)'",
                    data: [
                        "entityId": .string(entity.id.uuidString),
                        "entityName": .string(entity.name),
                    ]
                )
            } catch {
                return ToolExecutionResult(success: false, message: "\(error)", data: nil)
            }
        }
    }

    private func parsePosition(from dict: [String: JSONValue]?) -> SIMD3<Float> {
        guard let dict else { return .zero }
        return [dict["x"]?.floatValue ?? 0, dict["y"]?.floatValue ?? 0, dict["z"]?.floatValue ?? 0]
    }
}
