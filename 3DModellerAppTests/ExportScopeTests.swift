@testable import _D_Modeller
import CADModel
import CADModelKernel
import Foundation
import Testing

@Suite("Export scopes")
@MainActor
struct ExportScopeTests {
    private let plate = Part(
        name: "Plate",
        features: [
            Feature(name: "Box", kind: .primitive(PrimitiveFeature(.box(width: 60, depth: 40, height: 5)))),
            Feature(name: "Lug", kind: .primitive(PrimitiveFeature(.box(width: 5, depth: 5, height: 5)))),
        ])
    private let pin = Part(
        name: "Pin",
        features: [Feature(name: "Rod", kind: .primitive(PrimitiveFeature(.cylinder(radius: 2, height: 10))))])

    @Test("The choices are the document, each part, each body of a part with several, and each instance")
    func choices() async throws {
        let base = Instance(name: "Base", part: plate.id, grounded: true)
        let document = CADDocument(parts: [plate, pin], assembly: Assembly(instances: [base]))
        let result = try await RebuildEngine(kernel: OCCTGeometryKernel()).rebuild(document)

        let scopes = ExportScope.choices(for: document, result: result)

        #expect(
            scopes.map(\.label) == [
                "Whole assembly", "Part Plate", "Body Plate/Body1", "Body Plate/Body2", "Part Pin", "Instance Base",
            ])
        #expect(scopes.map(\.target)[0] == .document)
        #expect(scopes.map(\.target)[2] == .body(part: plate.id, body: "Body1"))
        #expect(scopes.map(\.target)[5] == .instance(base.id))
        #expect(scopes.map(\.suggestedName) == ["Assembly", "Plate", "Plate-Body1", "Plate-Body2", "Pin", "Base"])
    }

    @Test("Without instances the whole document is every part")
    func withoutAssembly() {
        let scopes = ExportScope.choices(for: CADDocument(parts: [pin]), result: nil)

        #expect(scopes.map(\.label) == ["All parts", "Part Pin"])
        #expect(scopes.first?.suggestedName == "Model")
    }

    @Test("The file name gets the format's extension")
    func fileName() {
        let scope = ExportScope(target: .document, label: "All parts", suggestedName: "Model")

        #expect(scope.fileName(for: .threeMF) == "Model.3mf")
        #expect(scope.fileName(for: .step) == "Model.step")
    }
}
