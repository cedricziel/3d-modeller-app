import Testing
import Foundation
@testable import SwiftUIAssistant

@Suite("ConversationManager Tests")
struct ConversationManagerTests {

    @Test("Add user message")
    @MainActor
    func testAddUserMessage() {
        let manager = ConversationManager()

        manager.addUserMessage("Hello!")

        #expect(manager.messages.count == 1)
        #expect(manager.messages.first?.role == .user)
        #expect(manager.messages.first?.content == "Hello!")
    }

    @Test("Add assistant message")
    @MainActor
    func testAddAssistantMessage() {
        let manager = ConversationManager()

        manager.addAssistantMessage("Hi there!")

        #expect(manager.messages.count == 1)
        #expect(manager.messages.first?.role == .assistant)
    }

    @Test("Add message with tool calls")
    @MainActor
    func testAddMessageWithToolCalls() {
        let manager = ConversationManager()

        let toolCall = ToolCall(
            id: "call_123",
            name: "create_cube",
            arguments: ["color": "red"]
        )

        manager.addAssistantMessage("Creating a cube", toolCalls: [toolCall])

        #expect(manager.messages.first?.toolCalls?.count == 1)
    }

    @Test("Clear conversation")
    @MainActor
    func testClearConversation() {
        let manager = ConversationManager()

        manager.addUserMessage("Message 1")
        manager.addAssistantMessage("Response 1")
        manager.addUserMessage("Message 2")

        #expect(manager.messages.count == 3)

        manager.clear()

        #expect(manager.messages.isEmpty)
    }

    @Test("Get conversation history for LLM")
    @MainActor
    func testGetHistory() {
        let manager = ConversationManager()

        manager.addUserMessage("First")
        manager.addAssistantMessage("Second")
        manager.addUserMessage("Third")

        let history = manager.history
        #expect(history.count == 3)
        #expect(history[0].content == "First")
        #expect(history[1].content == "Second")
        #expect(history[2].content == "Third")
    }

    @Test("Last message accessor")
    @MainActor
    func testLastMessage() {
        let manager = ConversationManager()

        #expect(manager.lastMessage == nil)

        manager.addUserMessage("Hello")
        #expect(manager.lastMessage?.content == "Hello")

        manager.addAssistantMessage("World")
        #expect(manager.lastMessage?.content == "World")
    }

    @Test("Add tool result message")
    @MainActor
    func testAddToolResultMessage() {
        let manager = ConversationManager()

        let result = ToolExecutionResult(
            success: true,
            message: "Created cube",
            data: ["id": "cube_1"]
        )

        manager.addToolResult(toolCallId: "call_123", result: result)

        #expect(manager.messages.count == 1)
        #expect(manager.messages.first?.role == .toolResult)
    }
}
