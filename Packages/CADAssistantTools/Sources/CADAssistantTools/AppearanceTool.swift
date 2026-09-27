import CADModel
import SwiftUIAssistant

public struct SetAppearanceTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "set_appearance"

    public let description = """
        Sets how a part or one instance looks: its colour as six hex digits (#2E7D32), and optionally metallic and \
        roughness, each 0 to 1. The call replaces the whole appearance. A part's appearance colours every instance of \
        it; an instance's own appearance overrides its part's, so one part can be placed in several colours. clear: \
        true removes the appearance (a part falls back to the viewer's colours, an instance to its part's). Colours \
        show in the app, render_views and STEP and 3MF exports.
        """

    public var parameters: [ToolParameter] {
        [
            .optionalString("part", description: "The part to colour; give this or 'instance'."),
            .optionalString("instance", description: "The instance to colour; give this or 'part'."),
            .optionalString("color", description: "Six hex digits such as #2E7D32."),
            ToolParameter(
                name: "metallic", type: .number, description: "0 (plastic, paint) to 1 (metal).", required: false
            ),
            ToolParameter(
                name: "roughness", type: .number, description: "0 (polished) to 1 (matte).", required: false
            ),
            ToolParameter(
                name: "clear", type: .boolean, description: "Removes the appearance instead.", required: false
            ),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.setAppearance(arguments)
    }
}

extension CADSession {
    func setAppearance(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { document throws(ToolError) in
            let arguments = try Arguments(
                raw, allowed: ["part", "instance", "color", "metallic", "roughness", "clear"]
            )
            let appearance = try Self.appearance(arguments)
            let partName = try arguments.string("part")
            let instanceName = try arguments.string("instance")
            let target: String
            let name: String
            switch (partName, instanceName) {
            case (let partName?, nil):
                let index = try document.partIndex(named: partName)
                document.parts[index].appearance = appearance
                (target, name) = ("part \(partName)", partName)
            case (nil, let instanceName?):
                let index = try document.instanceIndex(named: instanceName)
                document.assembly?.instances[index].appearance = appearance
                (target, name) = ("instance \(instanceName)", instanceName)
            default:
                throw ToolError("Give either 'part' or 'instance'.")
            }
            guard let appearance else {
                let fallback = instanceName == nil ? "" : "; it shows its part's"
                return WriteFocus(
                    actionName: "Clear appearance of \(name)",
                    summary: "Cleared the appearance of \(target)\(fallback)"
                )
            }
            return WriteFocus(
                actionName: "Set appearance of \(name)", summary: "Set the appearance of \(target) to \(appearance)"
            )
        }
    }

    /// The appearance the arguments describe, or nil to clear it.
    private static func appearance(_ arguments: Arguments) throws(ToolError) -> Appearance? {
        let factors = ["color", "metallic", "roughness"].filter(arguments.has)
        if try arguments.bool("clear") == true {
            guard factors.isEmpty else {
                throw ToolError("clear: true removes the appearance; leave out color, metallic and roughness.")
            }
            return nil
        }
        guard let text = try arguments.string("color") else {
            throw ToolError("Give 'color', or clear: true to remove the appearance.")
        }
        guard let color = HexColor(text) else {
            throw ToolError("'\(text)' is not a colour; give six hex digits such as #2E7D32.")
        }
        let (metallic, roughness) = (try arguments.factor("metallic"), try arguments.factor("roughness"))
        do throws(AppearanceError) {
            return try Appearance(color: color, metallic: metallic, roughness: roughness)
        } catch {
            throw ToolError(error.description)
        }
    }
}

private extension Arguments {
    func factor(_ key: String) throws(ToolError) -> Double? {
        guard has(key) else { return nil }
        switch try scalar(key) {
        case let .number(value)?: return value
        default: throw ToolError("'\(key)' must be a number between 0 and 1.")
        }
    }
}
