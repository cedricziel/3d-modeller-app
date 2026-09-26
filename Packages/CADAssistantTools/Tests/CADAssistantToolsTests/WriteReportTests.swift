import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("Write results")
struct WriteReportTests {
    private func blocks(_ count: Int, width: Scalar = 10) -> CADDocument {
        CADDocument(
            parameters: [Parameter(name: "w", expression: width)],
            parts: [
                Part(
                    name: "Plate",
                    features: (1...count).map { index in
                        Feature(
                            name: "Block\(index)",
                            kind: .primitive(
                                PrimitiveFeature(
                                    .box(width: "w", depth: 10, height: 10),
                                    placement: Placement(translation: Vector3(Scalar.number(Double(index) * 20), 0, 0))
                                )))
                    })
            ])
    }

    private func loaded(_ document: CADDocument) async throws -> Harness {
        let harness = Harness(document)
        try await harness.session.rebuild()
        return harness
    }

    @Test("Only bodies an edit changed are listed in full; the others share one line")
    func unchangedBodiesCollapse() async throws {
        let harness = try await loaded(blocks(3))

        let result = try await harness.call("edit_feature", ["feature": "Block2", "height": 5])

        #expect(result.message.contains("  Body2 (Plate): valid closed solid, 6 faces, 12 edges, volume 500 mm³"))
        #expect(result.message.contains("Unchanged bodies: Body1 (Plate), Body3 (Plate)"))
        #expect(!result.message.contains("Body1 (Plate): valid"))
    }

    @Test("A body that is gone is named")
    func removedBody() async throws {
        let harness = try await loaded(blocks(2))

        let result = try await harness.call("delete_feature", ["feature": "Block2"])

        #expect(result.message.contains("Removed bodies: Body2 (Plate)"))
        #expect(result.message.contains("Unchanged bodies: Body1 (Plate)"))
    }

    @Test("Long listing changes stop after 30 lines and point to get_listing")
    func listingDiffCapped() async throws {
        let harness = try await loaded(blocks(40))

        let result = try await harness.call("set_parameter", ["name": "w", "expression": -1])
        let lines = result.message.split(separator: "\n")
        let start = try #require(lines.firstIndex(of: "Listing changes:"))

        #expect(lines[(start + 1)...].count == 31)
        #expect(lines.last == "  … 52 more changed lines; call get_listing")
        #expect(result.message.contains("… 10 more status changes; call get_listing"))
    }

    @Test("A cut in a ten-body document costs a few hundred tokens")
    func writeResultBudget() async throws {
        let harness = try await loaded(blocks(10))

        let result = try await harness.call(
            "add_feature",
            [
                "name": "Hole", "type": "cylinder", "radius": 2, "height": 10,
                "placement": ["translation": [25, 5, 0]], "operation": "cut", "body": "Body1",
            ])

        #expect(result.success)
        #expect(result.message.count < 600, "\(result.message.count) characters:\n\(result.message)")
    }
}
