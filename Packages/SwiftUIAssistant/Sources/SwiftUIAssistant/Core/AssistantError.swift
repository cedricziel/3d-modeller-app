import Foundation

/// Errors that can occur in the assistant
public enum AssistantError: Error, LocalizedError, Sendable {
    /// The LLM provider returned an error
    case providerError(String)

    /// A tool execution failed
    case toolExecutionFailed(toolName: String, reason: String)

    /// The requested tool was not found
    case toolNotFound(String)

    /// Invalid tool arguments
    case invalidToolArguments(toolName: String, reason: String)

    /// Network error
    case networkError(String)

    /// Authentication failed
    case authenticationFailed(String)

    /// Rate limited
    case rateLimited(retryAfter: TimeInterval?)

    /// Response parsing failed
    case parsingError(String)

    /// Configuration error
    case configurationError(String)

    /// Unknown error
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .providerError(let message):
            return "LLM provider error: \(message)"
        case .toolExecutionFailed(let toolName, let reason):
            return "Tool '\(toolName)' failed: \(reason)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .invalidToolArguments(let toolName, let reason):
            return "Invalid arguments for tool '\(toolName)': \(reason)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds)) seconds."
            }
            return "Rate limited. Please try again later."
        case .parsingError(let message):
            return "Failed to parse response: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
