import Foundation

/// LLM provider that integrates with the Anthropic Claude API
public actor ClaudeProvider: LLMProvider {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let effort: String
    private let baseURL: URL
    private let idleTimeout: Duration
    private let session: URLSession

    /// Initialize the Claude provider
    /// - Parameters:
    ///   - apiKey: Your Anthropic API key
    ///   - model: The Claude model to use (default: claude-opus-5-5)
    ///   - maxTokens: Maximum tokens in the response, thinking included (default: 16000)
    ///   - effort: How much the model thinks: low, medium, high, xhigh or max (default: medium)
    ///   - idleTimeout: How long the response stream may send nothing before the request fails (default: 120 s)
    public init(
        apiKey: String,
        model: String = "claude-opus-5-5",
        maxTokens: Int = 16000,
        effort: String = "medium",
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        idleTimeout: Duration = .seconds(120),
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.effort = effort
        self.baseURL = baseURL
        self.idleTimeout = idleTimeout
        self.session = session
    }

    public func sendMessage(
        _ message: String,
        systemPrompt: String,
        conversationHistory: [Message],
        tools: [any AssistantTool]
    ) async throws -> LLMResponse {
        try await streamMessage(
            message, systemPrompt: systemPrompt, conversationHistory: conversationHistory, tools: tools
        ) { _ in }
    }

    public func streamMessage(
        _ message: String,
        systemPrompt: String,
        conversationHistory: [Message],
        tools: [any AssistantTool],
        onEvent: @escaping @Sendable (LLMStreamEvent) async -> Void
    ) async throws -> LLMResponse {
        let request = try buildRequest(systemPrompt: systemPrompt, messages: conversationHistory, tools: tools)
        let session = session
        let idleTimeout = idleTimeout
        let activity = ActivityClock()

        return try await withThrowingTaskGroup(of: LLMResponse?.self) { group in
            group.addTask {
                try await Self.receive(request, session: session, activity: activity, onEvent: onEvent)
            }
            group.addTask {
                try await activity.expire(after: idleTimeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let response = try await group.next() ?? nil else { throw URLError(.timedOut) }
            return response
        }
    }

    private static func receive(
        _ request: URLRequest,
        session: URLSession,
        activity: ActivityClock,
        onEvent: @Sendable (LLMStreamEvent) async -> Void
    ) async throws -> LLMResponse {
        let (bytes, response) = try await session.bytes(for: request)
        activity.touch()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AssistantError.networkError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            var body = Data()
            for try await byte in bytes {
                activity.touch()
                body.append(byte)
            }
            throw httpError(
                status: httpResponse.statusCode,
                body: String(data: body, encoding: .utf8) ?? "Unknown error",
                retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
            )
        }

        var accumulator = ClaudeStreamAccumulator()
        var line = Data()

        func process(_ line: Data) async throws {
            guard let payload = ClaudeStreamAccumulator.payload(ofLine: line) else { return }
            for event in try accumulator.apply(payload) {
                await onEvent(event)
                activity.touch()
            }
        }

        for try await byte in bytes {
            activity.touch()
            if byte == UInt8(ascii: "\n") {
                try await process(line)
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(byte)
            }
        }
        try await process(line)

        guard let finished = accumulator.response else {
            throw AssistantError.networkError("The response stream ended before the message was complete")
        }
        return finished
    }

    static func httpError(status: Int, body: String, retryAfter: TimeInterval?) -> AssistantError {
        switch status {
        case 401: .authenticationFailed("Invalid API key")
        case 429: .rateLimited(retryAfter: retryAfter)
        default: .providerError("HTTP \(status): \(body)")
        }
    }

    // MARK: - Request Building

    func buildRequest(
        systemPrompt: String,
        messages: [Message],
        tools: [any AssistantTool]
    ) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("/v1/messages")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // URLSession applies this between packets, not to the whole response.
        request.timeoutInterval = idleTimeout.seconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "output_config": ["effort": effort],
            "messages": messages.compactMap { formatMessage($0) },
            "stream": true,
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
            guard let context = message.context else {
                return ["role": "user", "content": message.content]
            }
            return [
                "role": "user",
                "content": [
                    ["type": "text", "text": "<context>\n\(context)\n</context>"],
                    ["type": "text", "text": message.content],
                ],
            ]

        case .assistant:
            if let rawContent = message.rawContent {
                return [
                    "role": "assistant",
                    "content": rawContent.map(\.anyValue),
                ]
            }

            var content: [[String: Any]] = []

            if !message.content.isEmpty {
                content.append([
                    "type": "text",
                    "text": message.content,
                ])
            }

            if let toolCalls = message.toolCalls {
                for call in toolCalls {
                    content.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": call.arguments.toAnyDict,
                    ])
                }
            }

            return [
                "role": "assistant",
                "content": content.isEmpty ? message.content : content,
            ]

        case .toolResult:
            guard let toolCallId = message.toolCallId else { return nil }

            return [
                "role": "user",
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": toolCallId,
                        "content": toolResultContent(message),
                    ]
                ],
            ]
        }
    }

    /// The text alone as a string, or with images as text and image blocks
    private func toolResultContent(_ message: Message) -> Any {
        guard !message.images.isEmpty else { return message.content }
        // The API refuses empty text blocks.
        var blocks: [[String: Any]] = message.content.isEmpty ? [] : [["type": "text", "text": message.content]]
        for image in message.images {
            if let caption = image.caption, !caption.isEmpty {
                blocks.append(["type": "text", "text": caption])
            }
            blocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mediaType,
                    "data": image.data.base64EncodedString(),
                ],
            ])
        }
        return blocks
    }

    private func formatTool(_ tool: any AssistantTool) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for param in tool.parameters {
            properties[param.name] = param.toJSONSchema().toAnyDict
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
                "required": required,
            ],
        ]
    }

    // MARK: - Response Parsing

    func parseResponse(_ data: Data) throws -> LLMResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AssistantError.parsingError("Invalid JSON response")
        }
        return try Self.parseMessage(json)
    }

    static func parseMessage(_ json: [String: Any]) throws -> LLMResponse {

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
        case "refusal":
            stopReason = .refusal
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
                if let text = block["text"] as? String {
                    textContent = (textContent ?? "") + text
                }

            case "tool_use":
                guard let id = block["id"] as? String,
                    let name = block["name"] as? String,
                    let input = block["input"] as? [String: Any],
                    let arguments = [String: JSONValue](fromAny: input)
                else {
                    continue
                }

                let toolCall = ToolCall(
                    id: id,
                    name: name,
                    arguments: arguments,
                    status: .pending
                )
                toolCalls.append(toolCall)

            default:
                break
            }
        }

        // Parse usage
        var usage: LLMResponse.Usage?
        if let usageDict = json["usage"] as? [String: Any],
            let inputTokens = usageDict["input_tokens"] as? Int,
            let outputTokens = usageDict["output_tokens"] as? Int
        {
            usage = LLMResponse.Usage(inputTokens: inputTokens, outputTokens: outputTokens)
        }

        return LLMResponse(
            content: textContent,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
            stopReason: stopReason,
            usage: usage,
            rawContent: contentArray.compactMap { JSONValue($0) }
        )
    }
}
