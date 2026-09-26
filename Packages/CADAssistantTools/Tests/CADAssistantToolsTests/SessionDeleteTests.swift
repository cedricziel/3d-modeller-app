import CADModel
import Foundation
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("Deleting a feature by id")
struct SessionDeleteTests {
    @Test("Deleting by id renumbers later body references like delete_feature, as one undo step")
    func renumbers() async throws {
        let harness = Harness(Fixtures.plate())
        let pin = try #require(harness.document.parts[0].features.first { $0.name == "Pin" })

        #expect(await harness.session.deleteFeature(id: pin.id) == nil)
        #expect(harness.commits == ["Delete Pin"])
        #expect(!harness.features().contains("Pin"))
        #expect(
            harness.document.parts[0].features.first { $0.name == "Merge" }?.kind
                == .boolean(BooleanFeature(operation: .union, target: "Body1", tools: ["Body2"])))
    }

    @Test("Deleting a feature whose body others use is refused and changes nothing")
    func refuses() async throws {
        let harness = Harness(Fixtures.plate())
        let before = harness.document
        let base = try #require(before.parts[0].features.first { $0.name == "Base" })

        let message = await harness.session.deleteFeature(id: base.id)

        #expect(
            message?.hasPrefix(
                "Nothing changed, because bodies that other features or instances use would no longer exist") == true)
        #expect(harness.document == before)
        #expect(harness.commits.isEmpty)
        #expect(await harness.session.deleteFeature(id: UUID()) == "The feature no longer exists.")
    }
}
