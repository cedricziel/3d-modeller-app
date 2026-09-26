import CADModel
import CADModelKernel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("Tools on the Open CASCADE kernel")
struct RealKernelTests {
    @Test("A plate with a parametric hole has the exact volume and stays a valid closed solid")
    func plateWithHole() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "Plate")]), kernel: OCCTGeometryKernel())
        let tools = Dictionary(uniqueKeysWithValues: CADTools.all(session: session).map { ($0.name, $0) })
        for (name, value) in [("width", 60), ("depth", 40), ("t", 10)] as [(String, JSONValue)] {
            #expect(
                try await tools["set_parameter"]!.execute(arguments: ["name": .string(name), "expression": value])
                    .success)
        }

        _ = try await tools["add_feature"]!.execute(arguments: [
            "name": "Plate", "type": "box", "width": "width", "depth": "depth", "height": "t",
        ])
        let hole = try await tools["add_feature"]!.execute(arguments: [
            "name": "Hole", "type": "cylinder", "radius": 2.75, "height": "t",
            "placement": ["translation": ["x": "width / 2", "y": "depth / 2"]], "operation": "cut", "body": "Body1",
        ])

        #expect(hole.success)
        #expect(hole.message.contains("Hole: ok"))
        #expect(hole.message.contains("Body1 (Plate): valid closed solid, 7 faces, 15 edges, volume 23762.4"))
        #expect(hole.message.contains("bounds (0, 0, 0) to (60, 40, 10)"))
        let volume = try #require(session.result?.bodies.first?.metrics?.volume)
        #expect(abs(volume - (24000 - Double.pi * 2.75 * 2.75 * 10)) < 0.01)
    }

    @Test("A kernel failure is reported as the feature's status and the document keeps the feature")
    func kernelFailure() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "P")]), kernel: OCCTGeometryKernel())
        let add = AddFeatureTool(session: session)
        _ = try await add.execute(arguments: ["type": "box", "width": 10, "depth": 10, "height": 10])

        let result = try await add.execute(arguments: [
            "type": "box", "width": 5, "depth": 5, "height": 5, "placement": ["translation": [100, 0, 0]],
            "operation": "intersect", "body": "Body1",
        ])

        #expect(result.success)
        #expect(result.message.contains("Box2: failed:"))
        #expect(session.document.parts[0].features.count == 2)
        #expect(result.message.contains("Body1 (P): valid closed solid, 6 faces, 12 edges, volume 1000 mm³"))
    }
}
