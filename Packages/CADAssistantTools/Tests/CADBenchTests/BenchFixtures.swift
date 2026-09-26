import CADBench
import CADModel
import Foundation
import SwiftUIAssistant

enum Bench {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let tasksDirectory = root.appending(path: "Bench/tasks")

    static func task(_ id: String) throws -> BenchTask { try TaskLoader.load(id: id, from: tasksDirectory) }

    static func check(_ json: String) throws -> Check {
        try JSONDecoder().decode(Check.self, from: Data(json.utf8))
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "cadbench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

func box(
    _ name: String, _ w: Scalar, _ d: Scalar, _ h: Scalar, at translation: Vector3 = Vector3(),
    operation: SolidOperation = .newBody, suppressed: Bool = false
) -> Feature {
    Feature(
        name: name, suppressed: suppressed,
        kind: .primitive(
            PrimitiveFeature(
                .box(width: w, depth: d, height: h), placement: Placement(translation: translation),
                operation: operation)))
}

actor ScriptedProvider: LLMProvider {
    enum Turn: Sendable {
        case respond(LLMResponse)
        case fail(AssistantError)
        case hang
        /// Answers after five seconds whatever happens, like a provider that ignores cancellation.
        case stall(LLMResponse)
    }

    private var turns: [Turn]
    private(set) var requests = 0

    init(_ turns: [Turn]) {
        self.turns = turns
    }

    func sendMessage(
        _ message: String, systemPrompt: String, conversationHistory: [Message], tools: [any AssistantTool]
    ) async throws -> LLMResponse {
        requests += 1
        guard !turns.isEmpty else {
            return LLMResponse(content: "(script ended)", toolCalls: nil, stopReason: .endTurn)
        }
        switch turns.removeFirst() {
        case .respond(let response): return response
        case .fail(let error): throw error
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        case .stall(let response):
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { continuation.resume() }
            }
            return response
        }
    }
}

func reply(_ text: String?, calls: [ToolCall] = [], input: Int = 0, output: Int = 0) -> ScriptedProvider.Turn {
    .respond(
        LLMResponse(
            content: text, toolCalls: calls.isEmpty ? nil : calls, stopReason: calls.isEmpty ? .endTurn : .toolUse,
            usage: LLMResponse.Usage(inputTokens: input, outputTokens: output)))
}
