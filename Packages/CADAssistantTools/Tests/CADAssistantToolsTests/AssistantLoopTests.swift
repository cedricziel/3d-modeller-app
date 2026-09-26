import CADModel
import CADModelKernel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

/// Plays back a fixed list of model turns and records every request it receives.
actor ScriptedProvider: LLMProvider {
    private var turns: [LLMResponse]
    private(set) var requests: [(systemPrompt: String, history: [Message])] = []

    init(_ turns: [LLMResponse]) {
        self.turns = turns
    }

    func sendMessage(
        _ message: String, systemPrompt: String, conversationHistory: [Message], tools: [any AssistantTool]
    ) async throws -> LLMResponse {
        requests.append((systemPrompt, conversationHistory))
        guard !turns.isEmpty else {
            return LLMResponse(content: "(script ended)", toolCalls: nil, stopReason: .endTurn)
        }
        return turns.removeFirst()
    }
}

@MainActor
@Suite("Assistant loop")
struct AssistantLoopTests {
    private func call(_ id: String, _ name: String, _ arguments: [String: JSONValue]) -> ToolCall {
        ToolCall(id: id, name: name, arguments: arguments)
    }

    @Test("A scripted model builds a plate with a hole through the tools, reading results between turns")
    func plateWithHole() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "Plate")]), kernel: OCCTGeometryKernel())
        var commits: [String] = []
        session.onCommit = { commits.append($1) }
        let provider = ScriptedProvider([
            LLMResponse(
                content: "Setting up parameters.",
                toolCalls: [
                    call("1", "set_parameter", ["name": "width", "expression": 60]),
                    call("2", "set_parameter", ["name": "depth", "expression": 40]),
                    call("3", "set_parameter", ["name": "t", "expression": 10]),
                    call("4", "set_parameter", ["name": "hole_d", "expression": 5.5]),
                ], stopReason: .toolUse),
            LLMResponse(
                content: nil,
                toolCalls: [
                    call(
                        "5", "add_feature",
                        ["name": "Plate", "type": "box", "width": "width", "depth": "depth", "height": "t"])
                ],
                stopReason: .toolUse),
            LLMResponse(
                content: nil,
                toolCalls: [
                    call(
                        "6", "add_feature",
                        [
                            "name": "Hole", "type": "cylinder", "radius": "hole_d / 2", "height": "t",
                            "placement": ["translation": ["x": "width / 2", "y": "depth / 2"]],
                            "operation": "cut", "body": "Body1",
                        ])
                ], stopReason: .toolUse),
            LLMResponse(content: "Built a 60×40×10 mm plate with a 5.5 mm hole.", toolCalls: nil, stopReason: .endTurn),
        ])
        let assistant = Assistant(
            provider: provider, tools: CADTools.all(session: session),
            contextProvider: { session.assistantContext() }, configuration: CADAssistantPrompt.configuration)

        try await assistant.send("Make a 60 by 40 by 10 plate with a 5.5 mm hole in the middle.")

        let requests = await provider.requests
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { $0.systemPrompt == CADAssistantPrompt.system })
        #expect(requests[0].history.first?.context?.contains("parameters: none\npart Plate\n  (no features)") == true)
        let results = requests[3].history.filter { $0.role == .toolResult }.map(\.content)
        #expect(results.count == 6)
        #expect(results.allSatisfy { $0.hasPrefix("Success: ") })
        #expect(results[5].contains("Hole: ok"))
        #expect(
            commits == [
                "Add Parameter width", "Add Parameter depth", "Add Parameter t", "Add Parameter hole_d", "Add Plate",
                "Add Hole",
            ])
        #expect(assistant.messages.last?.content == "Built a 60×40×10 mm plate with a 5.5 mm hole.")

        let body = try #require(session.result?.bodies.first)
        #expect(session.result?.bodies.count == 1)
        #expect(body.metrics?.isValid == true && body.metrics?.isClosed == true && body.metrics?.solidCount == 1)
        #expect(abs((body.metrics?.volume ?? 0) - (24000 - Double.pi * 2.75 * 2.75 * 10)) < 0.01)
        #expect(
            session.currentListing().contains(
                "Hole  cylinder r=(hole_d / 2) h=t at (width / 2, depth / 2, 0), cut Body1 → Body1  ok"))
    }

    @Test("A refused call reaches the model as an error and the next turn can correct it")
    func refusedCallIsReported() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "P")]), kernel: FakeKernel())
        let provider = ScriptedProvider([
            LLMResponse(
                content: nil, toolCalls: [call("1", "add_feature", ["type": "box", "width": 1])], stopReason: .toolUse),
            LLMResponse(
                content: nil,
                toolCalls: [call("2", "add_feature", ["type": "box", "width": 1, "depth": 1, "height": 1])],
                stopReason: .toolUse),
            LLMResponse(content: "Done.", toolCalls: nil, stopReason: .endTurn),
        ])
        let assistant = Assistant(
            provider: provider, tools: CADTools.all(session: session),
            contextProvider: { session.assistantContext() }, configuration: CADAssistantPrompt.configuration)

        try await assistant.send("A cube please")

        let results = await provider.requests[2].history.filter { $0.role == .toolResult }.map(\.content)
        #expect(results.count == 2)
        #expect(results.first == "Error: A box needs 'depth'.")
        #expect(results.last?.hasPrefix("Success: Added Box1 to part P") == true)
        #expect(session.document.parts[0].features.map(\.name) == ["Box1"])
    }

    @Test("The prompt asks for verification with renders and measurements after bigger changes")
    func promptVerification() {
        let prompt = CADAssistantPrompt.system
        #expect(prompt.contains("render_views"))
        #expect(prompt.contains("measure"))
        #expect(prompt.contains("bigger change"))
    }

    @Test("The prompt teaches sketching: fully constraining, tangentAt joints and sketch face names")
    func promptSketches() {
        let prompt = CADAssistantPrompt.system
        #expect(prompt.contains("add_sketch"))
        #expect(prompt.contains("tangentAt"))
        #expect(prompt.contains("fully constrained"))
        #expect(prompt.contains("Extrude1.side[Sketch1.line3]"))
    }
}
