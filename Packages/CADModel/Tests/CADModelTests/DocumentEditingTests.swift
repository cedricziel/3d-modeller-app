import Foundation
import Testing
@testable import CADModel

@Suite("Document editing")
struct DocumentEditingTests {
    private func document() -> (CADDocument, Feature, Feature) {
        let a = Feature(name: "A", kind: .primitive(PrimitiveFeature(.sphere(radius: 1))))
        let b = Feature(name: "B", kind: .primitive(PrimitiveFeature(.sphere(radius: 2))))
        return (CADDocument(parts: [Part(name: "P1", features: [a]), Part(name: "P2", features: [b])]), a, b)
    }

    @Test("Features are found by id across parts")
    func findsFeatures() {
        let (document, _, b) = document()
        #expect(document.feature(id: b.id) == b)
        #expect(document.feature(id: UUID()) == nil)
    }

    @Test("Updating and removing by id")
    func edits() {
        var (document, a, b) = document()
        #expect(document.updateFeature(id: b.id) { $0.suppressed = true })
        #expect(document.parts[1].features[0].suppressed)
        #expect(!document.updateFeature(id: UUID()) { $0.suppressed = true })
        #expect(document.removeFeature(id: a.id) == a)
        #expect(document.parts[0].features.isEmpty)
        #expect(document.removeFeature(id: a.id) == nil)
    }
}
