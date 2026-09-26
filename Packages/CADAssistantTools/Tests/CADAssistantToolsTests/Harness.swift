import CADModel
import Foundation
import SwiftUIAssistant

@testable import CADAssistantTools

/// A session over the fake kernel that records every commit, with shortcuts for calling tools by name.
@MainActor
final class Harness {
    let session: CADSession
    private(set) var commits: [String] = []

    init(
        _ document: CADDocument = CADDocument(parts: [Part(name: "Plate")]),
        kernel: any GeometryKernel = FakeKernel(),
        sketchSolver: any SketchSolving = FakeSketchSolver()
    ) {
        session = CADSession(document: document, kernel: kernel, sketchSolver: sketchSolver)
        session.onCommit = { [unowned self] _, action in commits.append(action) }
    }

    var document: CADDocument { session.document }

    func features(_ part: Int = 0) -> [String] { document.parts[part].features.map(\.name) }

    func call(_ tool: String, _ arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        let match = CADTools.all(session: session).first { $0.name == tool }
        guard let match else { fatalError("no tool \(tool)") }
        return try await match.execute(arguments: arguments)
    }

    /// Calls the tool and checks the call failed without touching the document or the undo history.
    func refused(_ tool: String, _ arguments: [String: JSONValue]) async throws -> String? {
        let before = document
        let commitCount = commits.count
        let result = try await call(tool, arguments)
        guard !result.success, document == before, commits.count == commitCount else { return nil }
        return result.message
    }
}

extension Fixtures {
    static func plateParametersOnly() -> CADDocument {
        CADDocument(parameters: plateParameters, parts: [Part(name: "Plate")])
    }
}
