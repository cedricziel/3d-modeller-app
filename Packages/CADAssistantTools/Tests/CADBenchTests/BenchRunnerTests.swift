import CADAssistantTools
import CADModel
import CADModelKernel
import SwiftUIAssistant
import Testing

@testable import CADBench

@MainActor
@Suite("Bench runner")
struct BenchRunnerTests {
    private let blockTask = BenchTask(
        id: "block", kind: .build, prompt: "Make a 10 × 20 × 30 block.",
        checks: [.gate, .volume(BodySelector(), expected: 6000, tolerance: 0.001)])

    private func runner(
        _ turns: [ScriptedProvider.Turn], timeout: Duration = .seconds(60), rounds: Int = 30
    ) -> BenchRunner<OCCTGeometryKernel> {
        let provider = ScriptedProvider(turns)
        return BenchRunner(
            kernel: OCCTGeometryKernel(),
            settings: RunSettings(model: "claude-opus-5-5", timeout: timeout, maxToolRounds: rounds),
            makeProvider: { provider })
    }

    private let addBlock = ToolCall(
        id: "1", name: "add_feature",
        arguments: ["name": "Block", "type": "box", "width": 10, "depth": 20, "height": 30])

    @Test("A completed run is graded and records tool calls, usage, cost, listing and transcript")
    func completedRun() async {
        let record = await runner([
            reply("Adding the block.", calls: [addBlock], input: 100, output: 20),
            reply("Built a 10 × 20 × 30 mm block.", input: 150, output: 10),
        ]).run(blockTask, attempt: 1)

        #expect(record.end == .completed && record.error == nil)
        #expect(record.passed, "\(record.grade.failures)")
        #expect(record.toolCalls == 1 && record.failedToolCalls == 0)
        #expect(
            record.usage
                == Usage(requests: 2, inputTokens: 250, outputTokens: 30, retries: 0, lastStopReason: "end_turn"))
        #expect(record.costUSD == Pricing.cost(model: "claude-opus-5-5", inputTokens: 250, outputTokens: 30))
        #expect(record.transcript.map(\.role) == ["user", "assistant", "tool_result", "assistant"])
        #expect(record.transcript[0].context?.contains("parameters: none") == true)
        #expect(record.transcript[1].toolCalls?.first?.name == "add_feature")
        #expect(record.transcript[2].text.hasPrefix("Success: Added Block"))
        #expect(record.listing.contains("Block  box 10×20×30 at origin → Body1  ok"))
        #expect(record.document.parts[0].features.map(\.name) == ["Block"])
        #expect(record.seconds >= 0)
        #expect(record.renders.map(\.view) == ViewDirection.allCases)
        #expect(record.renders.allSatisfy { $0.png.starts(with: [0x89, 0x50, 0x4E, 0x47]) })
        #expect(record.exportError == nil)
        #expect(record.step.map { String(decoding: $0, as: UTF8.self).hasPrefix("ISO-10303-21;") } == true)
    }

    @Test("A run without bodies records why it has no final STEP")
    func emptyRunHasNoStep() async {
        let record = await runner([reply("I will not model this.")]).run(blockTask, attempt: 1)

        #expect(record.step == nil)
        #expect(record.exportError?.hasPrefix("Nothing to export") == true)
    }

    @Test("The transcript keeps the captions of rendered views, not the images")
    func transcriptImages() async {
        let render = ToolCall(id: "2", name: "render_views", arguments: ["views": ["top"]])
        let record = await runner([
            reply(nil, calls: [addBlock]), reply(nil, calls: [render]), reply("Done."),
        ]).run(blockTask, attempt: 1)

        let entry = record.transcript.last { $0.role == "tool_result" }
        #expect(entry?.images?.count == 1)
        #expect(entry?.images?.first?.hasPrefix("top: looking down −Z") == true)
        #expect(record.transcript.first { $0.role == "tool_result" }?.images == nil)
    }

    @Test("A modify run starts from the rebuilt seed")
    func modifyStartsFromSeed() async {
        let seed = CADDocument(parts: [Part(name: "P", features: [box("Block", 10, 20, 30)])])
        let task = BenchTask(
            id: "m", kind: .modify, prompt: "Leave it.",
            checks: [
                .unchangedExcept(features: [], parameters: [], instances: [], joints: [], allowNewFeatures: false)
            ],
            seed: seed
        )
        let record = await runner([reply("Nothing to do.")]).run(task, attempt: 2)
        #expect(record.attempt == 2 && record.passed)
        #expect(record.transcript[0].context?.contains("Block  box 10×20×30 at origin → Body1  ok") == true)
    }

    @Test("A provider that never answers ends at the timeout and the run is still graded")
    func timeoutEndsRun() async {
        let record = await runner([.hang], timeout: .milliseconds(200)).run(blockTask, attempt: 1)
        #expect(record.end == .timedOut)
        #expect(!record.passed)
        #expect(record.grade.outcomes.first?.detail == "no bodies")
    }

    @Test("A provider that ignores cancellation still ends the run at the timeout")
    func timeoutWithoutCooperation() async {
        let record = await runner(
            [.stall(LLMResponse(content: "late", toolCalls: nil, stopReason: .endTurn))], timeout: .milliseconds(200)
        )
        .run(blockTask, attempt: 1)
        #expect(record.end == .timedOut)
        // The provider stalls for an hour; a loaded CI runner may take a few seconds to wake the timeout.
        #expect(record.seconds < 60)
    }

    @Test("Hitting the round limit is recorded")
    func maxRounds() async {
        let listing = ToolCall(id: "x", name: "get_listing", arguments: [:])
        let record = await runner(Array(repeating: reply(nil, calls: [listing]), count: 5), rounds: 3)
            .run(blockTask, attempt: 1)
        #expect(record.end == .maxToolRounds)
        #expect(record.toolCalls == 3)
    }

    @Test("A provider error ends the run with its message; refused tool calls are counted")
    func providerFailure() async {
        let bad = ToolCall(id: "b", name: "add_feature", arguments: ["type": "box", "width": 1])
        let record = await runner([reply(nil, calls: [bad]), .fail(.authenticationFailed("Invalid API key"))])
            .run(blockTask, attempt: 1)
        #expect(record.end == .failed)
        #expect(record.error == "Authentication failed: Invalid API key")
        #expect(record.failedToolCalls == 1)
    }
}
