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

    public init(_ message: Message) {
        role = message.role.rawValue
        text = message.content
        context = message.context
        toolCalls = message.toolCalls.map { $0.map { Call(id: $0.id, name: $0.name, arguments: $0.arguments) } }
        toolCallID = message.toolCallId
    }
}
