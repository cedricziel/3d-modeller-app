import Testing
@testable import SwiftUIAssistant

@Suite("MessageBubbleView Tests")
@MainActor
struct MessageBubbleViewTests {
    @Test("Tool-only assistant turns show no text bubble")
    func hidesEmptyBubble() {
        let message = Message.assistant(
            "  \n",
            toolCalls: [ToolCall(id: "1", name: "create_primitive", arguments: [:])]
        )
        #expect(MessageBubbleView(message: message).showsTextBubble == false)
    }

    @Test("Assistant turns with text show a bubble")
    func showsTextBubble() {
        #expect(MessageBubbleView(message: .assistant("Done")).showsTextBubble)
    }
}
