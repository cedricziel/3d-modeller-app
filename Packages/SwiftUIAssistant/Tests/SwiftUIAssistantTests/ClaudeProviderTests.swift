import Foundation
@testable import SwiftUIAssistant
import Testing

@Suite("ClaudeProvider Tests")
struct ClaudeProviderTests {
    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Requests allow a long wait, since a thinking model sends nothing until its answer is complete")
    func requestTimeout() async throws {
        let request = try await ClaudeProvider(apiKey: "test").buildRequest(
            systemPrompt: "system", messages: [.user("hi")], tools: [])
        #expect(request.timeoutInterval == 600)
    }

    @Test("Defaults to Claude Opus 5.5 with explicit effort and no disabled thinking")
    func defaultRequestShape() async throws {
        let provider = ClaudeProvider(apiKey: "test")
        let request = try await provider.buildRequest(
            systemPrompt: "system",
            messages: [.user("hi")],
            tools: []
        )
        let body = try body(of: request)

        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["max_tokens"] as? Int == 16000)
        #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "medium")
        #expect(body["thinking"] == nil)
    }

    @Test("Response keeps every content block, including thinking signatures")
    func parseKeepsRawContent() async throws {
        let json = """
            {
              "stop_reason": "tool_use",
              "content": [
                {"type": "thinking", "thinking": "", "signature": "sig-1"},
                {"type": "text", "text": "Creating a cube."},
                {"type": "tool_use", "id": "call_1", "name": "create_primitive", "input": {"type": "box", "visible": true}}
              ],
              "usage": {"input_tokens": 10, "output_tokens": 5, "cache_creation": {"ephemeral_5m_input_tokens": 0}}
            }
            """
        let provider = ClaudeProvider(apiKey: "test")
        let response = try await provider.parseResponse(Data(json.utf8))

        #expect(response.content == "Creating a cube.")
        #expect(response.toolCalls?.first?.id == "call_1")
        #expect(response.rawContent?.count == 3)
        #expect(response.rawContent?.first?["signature"]?.stringValue == "sig-1")
        #expect(response.rawContent?[2]["input"]?["visible"] == .bool(true))
        #expect(response.usage?.inputTokens == 10)
        #expect(response.usage?.outputTokens == 5)
    }

    @Test("Assistant turns with raw content are replayed unchanged")
    func replaysRawContent() async throws {
        let raw: [JSONValue] = [
            ["type": "thinking", "thinking": "", "signature": "sig-1"],
            ["type": "tool_use", "id": "call_1", "name": "create_primitive", "input": ["type": "box"]],
        ]
        let assistant = Message(
            role: .assistant,
            content: "",
            toolCalls: [
                ToolCall(id: "call_1", name: "create_primitive", arguments: ["type": "box"], status: .completed)
            ],
            rawContent: raw
        )
        let provider = ClaudeProvider(apiKey: "test")
        let request = try await provider.buildRequest(
            systemPrompt: "system",
            messages: [.user("make a cube"), assistant, .toolResult(toolCallId: "call_1", content: "ok")],
            tools: []
        )
        let messages = try #require(try body(of: request)["messages"] as? [[String: Any]])
        let content = try #require(messages[1]["content"] as? [[String: Any]])

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "thinking")
        #expect(content[0]["signature"] as? String == "sig-1")
        #expect(content[1]["type"] as? String == "tool_use")
    }

    @Test("A user message with context sends the context as a text block before the message")
    func userContextBlock() async throws {
        let provider = ClaudeProvider(apiKey: "test")
        let request = try await provider.buildRequest(
            systemPrompt: "system",
            messages: [.user("add a hole", context: "part Plate")],
            tools: []
        )
        let messages = try #require(try body(of: request)["messages"] as? [[String: Any]])
        let content = try #require(messages[0]["content"] as? [[String: Any]])

        #expect(content.count == 2)
        #expect(content[0]["text"] as? String == "<context>\npart Plate\n</context>")
        #expect(content[1]["text"] as? String == "add a hole")
    }

    @Test("Tool parameters with a custom schema are sent unchanged")
    func customParameterSchema() async throws {
        let provider = ClaudeProvider(apiKey: "test")
        let tool = MockTool(
            id: "t", name: "t", description: "d",
            parameters: [.custom("width", description: "mm", required: true, schema: ["type": ["number", "string"]])]
        )
        let request = try await provider.buildRequest(systemPrompt: "s", messages: [.user("x")], tools: [tool])
        let tools = try #require(try body(of: request)["tools"] as? [[String: Any]])
        let schema = try #require(tools[0]["input_schema"] as? [String: Any])
        let width = try #require((schema["properties"] as? [String: Any])?["width"] as? [String: Any])

        #expect(width["type"] as? [String] == ["number", "string"])
        #expect(width["description"] as? String == "mm")
        #expect(schema["required"] as? [String] == ["width"])
    }
}
