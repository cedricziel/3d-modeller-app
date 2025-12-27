import Foundation

/// Protocol for providing context to the assistant
///
/// The host application implements this protocol to give the assistant
/// awareness of the current state (e.g., selected objects, scene contents).
public protocol AssistantContext: Sendable {
    /// Serialize the context to a dictionary for JSON encoding
    func serialize() -> [String: Any]

    /// Human-readable description of the context for the system prompt
    var contextDescription: String { get }
}

// MARK: - Default Implementation

public extension AssistantContext {
    /// Default serialization uses the description
    func serialize() -> [String: Any] {
        ["description": contextDescription]
    }
}

// MARK: - Empty Context

/// An empty context for when no context is needed
public struct EmptyContext: AssistantContext {
    public init() {}

    public func serialize() -> [String: Any] {
        [:]
    }

    public var contextDescription: String {
        "No context available."
    }
}
