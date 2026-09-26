import CADModel
import Foundation
import Testing

@testable import CADBench

@Suite("Document comparison")
struct DocumentComparisonTests {
    let seed = CADDocument(
        parameters: [Parameter(name: "w", expression: 80), Parameter(name: "t", expression: 6)],
        parts: [
            Part(name: "P", features: [box("Plate", "w", 50, "t"), box("Hole", 5, 5, "t", operation: .cut("Body1"))])
        ])

    private func differences(
        _ document: CADDocument, features: Set<String> = [], parameters: Set<String> = [], allowNew: Bool = false
    ) -> [String] {
        DocumentComparison.differences(
            from: seed, to: document, features: features, parameters: parameters, allowNewFeatures: allowNew)
    }

    @Test("An identical document has no differences, even with fresh ids")
    func identical() {
        var copy = seed
        copy.parts[0].features = copy.parts[0].features.map {
            var feature = $0
            feature.id = UUID()
            return feature
        }
        #expect(differences(copy).isEmpty)
    }

    @Test("Parameter edits count unless exempt; new parameters are always fine; removal counts")
    func parameters() {
        var edited = seed
        edited.parameters[1].expression = 10
        edited.parameters.append(Parameter(name: "hole_x", expression: 40))
        #expect(differences(edited) == ["parameter t changed from 6 to 10"])
        #expect(differences(edited, parameters: ["t"]).isEmpty)
        edited.parameters.remove(at: 0)
        #expect(differences(edited, parameters: ["t"]) == ["parameter w was removed"])
    }

    @Test("Feature edits, additions, removals and reordering count unless exempt or allowed")
    func features() {
        var edited = seed
        edited.parts[0].features[1] = box("Hole", 5, 5, "t", at: Vector3(10, 0, 0), operation: .cut("Body1"))
        #expect(differences(edited) == ["feature Hole changed"])
        #expect(differences(edited, features: ["Hole"]).isEmpty)

        var added = seed
        added.parts[0].features.append(box("Hole2", 5, 5, "t", operation: .cut("Body1")))
        #expect(differences(added) == ["feature Hole2 was added"])
        #expect(differences(added, allowNew: true).isEmpty)
        #expect(differences(added, features: ["Hole2"]).isEmpty)

        var removed = seed
        removed.parts[0].features.removeLast()
        #expect(differences(removed) == ["feature Hole was removed"])

        var reordered = seed
        reordered.parts[0].features.reverse()
        #expect(differences(reordered) == ["features of part P were reordered"])

        var suppressed = seed
        suppressed.parts[0].features[1].suppressed = true
        #expect(differences(suppressed) == ["feature Hole changed"])
    }

    @Test("A body inserted earlier renumbers references without counting as a change")
    func renumbering() {
        var edited = seed
        edited.parts[0].features.insert(box("Boss", 1, 1, 1), at: 0)
        edited.parts[0].features[2] = box("Hole", 5, 5, "t", operation: .cut("Body2"))
        #expect(differences(edited, allowNew: true).isEmpty)
        #expect(differences(edited) == ["feature Boss was added"])
    }

    @Test("Parts added or removed count")
    func parts() {
        var edited = seed
        edited.parts.append(Part(name: "Q"))
        #expect(differences(edited) == ["part Q was added"])
        edited.parts.removeFirst()
        #expect(differences(edited) == ["part P was removed", "part Q was added"])
    }
}
