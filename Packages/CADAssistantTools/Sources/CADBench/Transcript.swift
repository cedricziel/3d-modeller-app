import SwiftUIAssistant

public struct TranscriptEntry: Sendable, Codable, Equatable {
    public struct Call: Sendable, Codable, Equatable {
        public let id: String
        public let name: String
        public let arguments: [String: JSONValue]
    }

    public let role: String
    public let text: String
    public let context: String?
    public let toolCalls: [Call]?
    public let toolCallID: String?
    /// Captions of the images a tool returned; the images themselves are not kept.
    public let images: [String]?

    public init(_ message: Message) {
        role = message.role.rawValue
        text = message.content
        context = message.context
        toolCalls = message.toolCalls.map { $0.map { Call(id: $0.id, name: $0.name, arguments: $0.arguments) } }
        toolCallID = message.toolCallId
        images = message.images.isEmpty ? nil : message.images.map { $0.caption ?? $0.mediaType }
    }
}
