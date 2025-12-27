import Foundation

/// LLM provider that integrates with the Anthropic Claude API
public actor ClaudeProvider: LLMProvider {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let baseURL: URL

    /// Initialize the Claude provider
    /// - Parameters:
    ///   - apiKey: Your Anthropic API key
    ///   - model: The Claude model to use (default: claude-sonnet-4-20250514)
    ///   - maxTokens: Maximum tokens in the response (default: 4096)
    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-20250514",
        maxTokens: Int = 4096,
        baseURL: URL = URL(string: "https://api.anthropic.com")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.baseURL = baseURL
    }

    public func sendMessage(
        _ message: String,
        systemPrompt: String,
        conversationHistory: [Message],
        tools: [any AssistantTool]
    ) async throws -> LLMResponse {
        let request = try buildRequest(
            systemPrompt: systemPrompt,
            messages: conversationHistory,
            tools: tools
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AssistantError.networkError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"

            if httpResponse.statusCode == 401 {
                throw AssistantError.authenticationFailed("Invalid API key")
            } else if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Double($0) }
                throw AssistantError.rateLimited(retryAfter: retryAfter)
            } else {
                throw AssistantError.providerError("HTTP \(httpResponse.statusCode): \(errorBody)")
            }
        }

        return try parseResponse(data)
    }

    // MARK: - Request Building

    private func buildRequest(
        systemPrompt: String,
        messages: [Message],
        tools: [any AssistantTool]
    ) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("/v1/messages")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messages.compactMap { formatMessage($0) }
        ]

        if !tools.isEmpty {
            body["tools"] = tools.map { formatTool($0) }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func formatMessage(_ message: Message) -> [String: Any]? {
        switch message.role {
        case .system:
            // System messages are handled separately
            return nil

        case .user:
            return [
                "role": "user",
                "content": message.content
            ]

        case .assistant:
            var content: [[String: Any]] = []

            if !message.content.isEmpty {
                content.append([
                    "type": "text",
                    "text": message.content
                ])
            }

            if let toolCalls = message.toolCalls {
                for call in toolCalls {
                    content.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": call.arguments
                    ])
                }
            }

            return [
                "role": "assistant",
                "content": content.isEmpty ? message.content : content
            ]

        case .toolResult:
            guard let toolCallId = message.toolCallId else { return nil }

            return [
                "role": "user",
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": toolCallId,
                        "content": message.content
                    ]
                ]
            ]
        }
    }

    private func formatTool(_ tool: any AssistantTool) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for param in tool.parameters {
            properties[param.name] = param.toJSONSchema()
            if param.required {
                required.append(param.name)
            }
        }

        return [
            "name": tool.name,
            "description": tool.description,
            "input_schema": [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        ]
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> LLMResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AssistantError.parsingError("Invalid JSON response")
        }

        // Parse stop reason
        let stopReasonString = json["stop_reason"] as? String ?? "end_turn"
        let stopReason: LLMResponse.StopReason

        switch stopReasonString {
        case "end_turn":
            stopReason = .endTurn
        case "tool_use":
            stopReason = .toolUse
        case "max_tokens":
            stopReason = .maxTokens
        case "stop_sequence":
            stopReason = .stopSequence
        default:
            stopReason = .endTurn
        }

        // Parse content
        guard let contentArray = json["content"] as? [[String: Any]] else {
            throw AssistantError.parsingError("Missing content in response")
        }

        var textContent: String?
        var toolCalls: [ToolCall] = []

        for block in contentArray {
            guard let type = block["type"] as? String else { continue }

            switch type {
            case "text":
                textContent = block["text"] as? String

            case "tool_use":
                guard let id = block["id"] as? String,
                      let name = block["name"] as? String,
                      let input = block["input"] as? [String: Any] else {
                    continue
                }

                let toolCall = ToolCall(
                    id: id,
                    name: name,
                    arguments: input,
                    status: .pending
                )
                toolCalls.append(toolCall)

            default:
                break
            }
        }

        // Parse usage
        var usage: LLMResponse.Usage?
        if let usageDict = json["usage"] as? [String: Int],
           let inputTokens = usageDict["input_tokens"],
           let outputTokens = usageDict["output_tokens"] {
            usage = LLMResponse.Usage(inputTokens: inputTokens, outputTokens: outputTokens)
        }

        return LLMResponse(
            content: textContent,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
            stopReason: stopReason,
            usage: usage
        )
    }
}
