import Foundation
import Synchronization

/// Builds a Messages API response from its server-sent events
struct ClaudeStreamAccumulator {
    private var message: [String: Any] = [:]
    private var blocks: [Int: [String: Any]] = [:]
    private var toolInputs: [Int: String] = [:]

    /// The complete response, once `message_stop` has arrived
    private(set) var response: LLMResponse?

    /// The JSON object on a `data:` line; other lines carry nothing the accumulator needs
    static func payload(ofLine line: Data) -> [String: Any]? {
        var line = line
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        let prefix = Data("data:".utf8)
        guard line.starts(with: prefix) else { return nil }
        let data = line.dropFirst(prefix.count)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Applies one event and returns what the caller should see of it
    mutating func apply(_ event: [String: Any]) throws -> [LLMStreamEvent] {
        let index = event["index"] as? Int ?? 0

        switch event["type"] as? String {
        case "message_start":
            message = event["message"] as? [String: Any] ?? [:]
            return []

        case "content_block_start":
            let block = event["content_block"] as? [String: Any] ?? [:]
            blocks[index] = block
            switch block["type"] as? String {
            case "thinking": return [.thinking(block["thinking"] as? String ?? "")]
            case "redacted_thinking": return [.thinking("")]
            case "tool_use":
                toolInputs[index] = ""
                return []
            case "text":
                let text = block["text"] as? String ?? ""
                return text.isEmpty ? [] : [.text(text)]
            default: return []
            }

        case "content_block_delta":
            return applyDelta(event["delta"] as? [String: Any] ?? [:], at: index)

        case "content_block_stop":
            try finishToolInput(at: index)
            return []

        case "message_delta":
            if let delta = event["delta"] as? [String: Any] {
                for (key, value) in delta { message[key] = value }
            }
            if let usage = event["usage"] as? [String: Any] {
                var merged = message["usage"] as? [String: Any] ?? [:]
                for (key, value) in usage where !(value is NSNull) { merged[key] = value }
                message["usage"] = merged
            }
            return []

        case "message_stop":
            message["content"] = blocks.keys.sorted().compactMap { blocks[$0] }
            response = try ClaudeProvider.parseMessage(message)
            return []

        case "error":
            throw Self.streamError(event["error"] as? [String: Any] ?? [:])

        default:
            return []
        }
    }

    private mutating func applyDelta(_ delta: [String: Any], at index: Int) -> [LLMStreamEvent] {
        switch delta["type"] as? String {
        case "text_delta":
            let text = delta["text"] as? String ?? ""
            append(text, to: "text", at: index)
            return [.text(text)]
        case "thinking_delta":
            let thinking = delta["thinking"] as? String ?? ""
            append(thinking, to: "thinking", at: index)
            return [.thinking(thinking)]
        case "signature_delta":
            blocks[index]?["signature"] = delta["signature"]
            return []
        case "input_json_delta":
            toolInputs[index, default: ""] += delta["partial_json"] as? String ?? ""
            return []
        case "citations_delta":
            if let citation = delta["citation"] {
                let citations = blocks[index]?["citations"] as? [Any] ?? []
                blocks[index]?["citations"] = citations + [citation]
            }
            return []
        default:
            return []
        }
    }

    private mutating func append(_ text: String, to key: String, at index: Int) {
        let current = blocks[index]?[key] as? String ?? ""
        blocks[index]?[key] = current + text
    }

    private mutating func finishToolInput(at index: Int) throws {
        guard let json = toolInputs.removeValue(forKey: index) else { return }
        guard !json.isEmpty else {
            blocks[index]?["input"] = [String: Any]()
            return
        }
        guard let input = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            let name = blocks[index]?["name"] as? String ?? "tool"
            throw AssistantError.parsingError("The input for \(name) is not a JSON object")
        }
        blocks[index]?["input"] = input
    }

    /// Maps an `error` event to the error its HTTP status would have produced
    static func streamError(_ error: [String: Any]) -> AssistantError {
        let type = error["type"] as? String ?? "unknown_error"
        let message = error["message"] as? String ?? type
        let statuses = [
            "invalid_request_error": 400, "authentication_error": 401, "billing_error": 402,
            "permission_error": 403, "not_found_error": 404, "request_too_large": 413,
            "rate_limit_error": 429, "api_error": 500, "timeout_error": 504, "overloaded_error": 529,
        ]
        guard let status = statuses[type] else { return .providerError("\(type): \(message)") }
        return ClaudeProvider.httpError(status: status, body: "\(type): \(message)", retryAfter: nil)
    }
}

/// Remembers when a stream last made progress, and fails once it has been quiet for too long
final class ActivityClock: Sendable {
    private let last = Mutex(ContinuousClock.now)

    func touch() {
        last.withLock { $0 = .now }
    }

    func expire(after timeout: Duration) async throws {
        while true {
            let deadline = last.withLock { $0 } + timeout
            if ContinuousClock.now >= deadline { throw URLError(.timedOut) }
            try await Task.sleep(until: deadline, clock: .continuous)
        }
    }
}

extension Duration {
    var seconds: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
