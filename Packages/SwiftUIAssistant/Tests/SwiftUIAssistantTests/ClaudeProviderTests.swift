import Foundation
import Testing

@testable import SwiftUIAssistant

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

    @Test("A tool result with images sends its text, then each caption and image as base64 blocks")
    func imageToolResult() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let result = Message.toolResult(
            toolCallId: "call_1", content: "Success: 1 view",
            images: [ToolImage(data: png, caption: "top: looking down -Z")])
        let request = try await ClaudeProvider(apiKey: "test").buildRequest(
            systemPrompt: "s", messages: [.user("look"), result], tools: [])
        let messages = try #require(try body(of: request)["messages"] as? [[String: Any]])
        let blocks = try #require(messages[1]["content"] as? [[String: Any]])
        let toolResult = try #require(blocks.first)
        let content = try #require(toolResult["content"] as? [[String: Any]])

        #expect(toolResult["type"] as? String == "tool_result")
        #expect(toolResult["tool_use_id"] as? String == "call_1")
        #expect(content.count == 3)
        #expect(content[0]["type"] as? String == "text" && content[0]["text"] as? String == "Success: 1 view")
        #expect(content[1]["text"] as? String == "top: looking down -Z")
        #expect(content[2]["type"] as? String == "image")
        let source = try #require(content[2]["source"] as? [String: Any])
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "image/png")
        #expect(source["data"] as? String == png.base64EncodedString())
    }

    @Test("A text-only tool result next to an image result keeps plain string content")
    func mixedToolResults() async throws {
        let request = try await ClaudeProvider(apiKey: "test").buildRequest(
            systemPrompt: "s",
            messages: [
                .user("look"),
                .toolResult(toolCallId: "a", content: "pictures", images: [ToolImage(data: Data([1]))]),
                .toolResult(toolCallId: "b", content: "Success: ok"),
            ],
            tools: [])
        let messages = try #require(try body(of: request)["messages"] as? [[String: Any]])
        let first = try #require((messages[1]["content"] as? [[String: Any]])?.first)
        let second = try #require((messages[2]["content"] as? [[String: Any]])?.first)

        #expect((first["content"] as? [[String: Any]])?.count == 2)
        #expect(second["content"] as? String == "Success: ok")
    }

    @Test("Empty text and captions are left out of an image tool result")
    func emptyTextBlocks() async throws {
        let request = try await ClaudeProvider(apiKey: "test").buildRequest(
            systemPrompt: "s",
            messages: [
                .user("look"),
                .toolResult(toolCallId: "a", content: "", images: [ToolImage(data: Data([1]), caption: "")]),
            ],
            tools: [])
        let messages = try #require(try body(of: request)["messages"] as? [[String: Any]])
        let result = try #require((messages[1]["content"] as? [[String: Any]])?.first)
        let content = try #require(result["content"] as? [[String: Any]])

        #expect(content.map { $0["type"] as? String } == ["image"])
    }
}
