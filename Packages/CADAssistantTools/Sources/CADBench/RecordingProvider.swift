import Foundation
import SwiftUIAssistant

public struct Usage: Sendable, Codable, Equatable {
    public var requests: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var retries: Int
    public var lastStopReason: String?

    public init(
        requests: Int = 0, inputTokens: Int = 0, outputTokens: Int = 0, retries: Int = 0,
        lastStopReason: String? = nil
    ) {
        self.requests = requests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.retries = retries
        self.lastStopReason = lastStopReason
    }
}

/// Wraps a provider to add up token usage, which `Assistant` does not keep, and to retry transient failures.
public actor RecordingProvider: LLMProvider {
    private let base: any LLMProvider
    private let retryDelays: [Duration]
    public private(set) var usage = Usage()

    public init(_ base: any LLMProvider, retryDelays: [Duration] = [.seconds(10), .seconds(30)]) {
        self.base = base
        self.retryDelays = retryDelays
    }

    public func sendMessage(
        _ message: String, systemPrompt: String, conversationHistory: [Message], tools: [any AssistantTool]
    ) async throws -> LLMResponse {
        var attempt = 0
        while true {
            usage.requests += 1
            do {
                let response = try await base.sendMessage(
                    message, systemPrompt: systemPrompt, conversationHistory: conversationHistory, tools: tools)
                if let tokens = response.usage {
                    usage.inputTokens += tokens.inputTokens
                    usage.outputTokens += tokens.outputTokens
                }
                usage.lastStopReason = response.stopReason.rawValue
                return response
            } catch  where attempt < retryDelays.count && !Task.isCancelled && Self.isTransient(error) {
                try await Task.sleep(for: retryDelays[attempt])
                attempt += 1
                usage.retries += 1
            }
        }
    }

    static func isTransient(_ error: any Error) -> Bool {
        if let error = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]
                .contains(error.code)
        }
        switch error as? AssistantError {
        case .rateLimited?, .networkError?: return true
        case .providerError(let message)?: return message.hasPrefix("HTTP 5")
        default: return false
        }
    }
}
