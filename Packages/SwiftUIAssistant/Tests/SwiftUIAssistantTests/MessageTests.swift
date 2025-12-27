import Testing
import Foundation
@testable import SwiftUIAssistant

@Suite("Message Model Tests")
struct MessageTests {

    @Test("User message creation")
    func testUserMessageCreation() {
        let message = Message(role: .user, content: "Hello, assistant!")

        #expect(message.role == .user)
        #expect(message.content == "Hello, assistant!")
        #expect(message.toolCalls == nil)
        #expect(message.id != UUID())
    }

    @Test("Assistant message creation")
    func testAssistantMessageCreation() {
        let message = Message(role: .assistant, content: "Hello! How can I help?")

        #expect(message.role == .assistant)
        #expect(message.content == "Hello! How can I help?")
    }

    @Test("System message creation")
    func testSystemMessageCreation() {
        let message = Message(role: .system, content: "You are a helpful assistant.")

        #expect(message.role == .system)
    }

    @Test("Message with tool calls")
    func testMessageWithToolCalls() {
        let toolCall = ToolCall(
            id: "call_123",
            name: "create_primitive",
            arguments: ["type": "cube", "color": "red"]
        )

        let message = Message(
            role: .assistant,
            content: "I'll create a red cube for you.",
            toolCalls: [toolCall]
        )

        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?.first?.name == "create_primitive")
    }

    @Test("Message timestamp is set")
    func testMessageTimestamp() {
        let before = Date()
        let message = Message(role: .user, content: "Test")
        let after = Date()

        #expect(message.timestamp >= before)
        #expect(message.timestamp <= after)
    }
}
