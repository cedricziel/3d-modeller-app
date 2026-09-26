import Foundation
import Testing

@testable import SwiftUIAssistant

@Suite("ToolParameter")
struct ToolParameterTests {
    @Test("A custom schema replaces the generated one and keeps the description")
    func customSchema() {
        let parameter = ToolParameter.custom(
            "width",
            description: "Width in mm",
            schema: ["anyOf": [["type": "number"], ["type": "string"]]]
        )

        #expect(parameter.required == false)
        #expect(
            parameter.toJSONSchema() == [
                "anyOf": [["type": "number"], ["type": "string"]],
                "description": "Width in mm",
            ])
    }

    @Test("Parameters without a custom schema keep the generated one")
    func generatedSchema() {
        let parameter = ToolParameter.enumParameter("mode", description: "Mode", values: ["a", "b"])

        #expect(parameter.toJSONSchema() == ["type": "string", "description": "Mode", "enum": ["a", "b"]])
    }
}
