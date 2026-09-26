import CADModel
import Foundation
import Testing

@testable import CADAssistantTools

@Suite("Document listing")
struct DocumentListingTests {
    @Test("A rebuilt document lists parameters with values and every feature with its body and status")
    func plate() async throws {
        let document = Fixtures.plate()
        let result = try await RebuildEngine(kernel: FakeKernel()).rebuild(document)

        #expect(
            DocumentListing.render(document, result: result) == """
                parameters: width = 60, depth = 40, t = 10, hole_d = 5.5, hole_r = hole_d / 2 (= 2.75)
                part Plate
                  Base  box width×depth×t at origin → Body1  ok
                  Hole  cylinder r=hole_r h=t at (width / 2, depth / 2, 0), cut Body1 → Body1  ok
                  Pin  cylinder r=2 h=5 at (0, 0, 10) rotated 90° about (1, 0, 0) → Body2  suppressed
                  BadCone  cone r1=3 r2=3 h=5 at origin → Body3  failed: cone radii must differ
                  Merge  union Body1 with Body3 → Body1  skipped: depends on BadCone
                  Move  transform Body1 moved by (10, 0, 0) → Body1  ok
                """)
    }

    @Test("Without a rebuild result features read as not built, suppressed ones as suppressed")
    func notBuilt() {
        #expect(
            DocumentListing.render(Fixtures.plate(), result: nil).split(separator: "\n").map(String.init)[2...4] == [
                "  Base  box width×depth×t at origin → Body1  not built",
                "  Hole  cylinder r=hole_r h=t at (width / 2, depth / 2, 0), cut Body1 → Body1  not built",
                "  Pin  cylinder r=2 h=5 at (0, 0, 10) rotated 90° about (1, 0, 0) → Body2  suppressed",
            ])
    }

    @Test("Empty documents, empty parts and failing parameters are listed plainly")
    func emptyAndFailing() {
        let document = CADDocument(
            parameters: [Parameter(name: "a", expression: "1 / 0"), Parameter(name: "b", expression: "a + 1")],
            parts: [Part(name: "Empty")])

        #expect(
            DocumentListing.render(document, result: nil) == """
                parameters: a = 1 / 0 (error: division by zero), b = a + 1 (error: parameter 'a' has an error)
                part Empty
                  (no features)
                """)
        #expect(DocumentListing.render(CADDocument(parts: []), result: nil) == "parameters: none")
    }

    @Test("Compound expressions are parenthesised where they would read ambiguously")
    func compoundExpressions() {
        let document = CADDocument(
            parts: [
                Part(
                    name: "P",
                    features: [
                        Fixtures.box("B", "w + 1", 2, "h * 2"),
                        Feature(
                            name: "C",
                            kind: .primitive(
                                PrimitiveFeature(
                                    .cone(bottomRadius: "r - 1", topRadius: 0, height: 3),
                                    placement: Placement(rotationDegrees: "a / 2"), operation: .join("Body1")))),
                        Feature(
                            name: "T",
                            kind: .transform(
                                TransformFeature(
                                    body: "Body1",
                                    placement: Placement(
                                        translation: Vector3(1, 2, 3), rotationAxis: Vector3(0, 0, 1),
                                        rotationDegrees: 45)))),
                        Feature(name: "U", kind: .transform(TransformFeature(body: "Body1", placement: .identity))),
                        Feature(
                            name: "S",
                            kind: .boolean(
                                BooleanFeature(operation: .subtract, target: "Body1", tools: ["Body2", "Body3"]))),
                        Feature(
                            name: "I",
                            kind: .boolean(BooleanFeature(operation: .intersect, target: "Body1", tools: ["Body2"]))),
                        Feature(
                            name: "Tor", kind: .primitive(PrimitiveFeature(.torus(majorRadius: 5, minorRadius: 1)))),
                        Feature(name: "Sph", kind: .primitive(PrimitiveFeature(.sphere(radius: 1.25)))),
                    ])
            ])

        #expect(
            DocumentListing.render(document, result: nil) == """
                parameters: none
                part P
                  B  box (w + 1)×2×(h * 2) at origin → Body1  not built
                  C  cone r1=(r - 1) r2=0 h=3 at origin rotated (a / 2)° about (0, 0, 1), join Body1 → Body1  not built
                  T  transform Body1 rotated 45° about (0, 0, 1), then moved by (1, 2, 3) → Body1  not built
                  U  transform Body1 unchanged → Body1  not built
                  S  subtract Body2, Body3 from Body1 → Body1  not built
                  I  intersect Body1 with Body2 → Body1  not built
                  Tor  torus R=5 r=1 at origin → Body2  not built
                  Sph  sphere r=1.25 at origin → Body3  not built
                """)
    }

    @Test("Numbers are shown with at most three decimals and no negative zero")
    func numbers() {
        #expect(Format.number(2.75) == "2.75")
        #expect(Format.number(1.0 / 3.0) == "0.333")
        #expect(Format.number(-0.0001) == "0")
        #expect(Format.number(24000) == "24000")
        #expect(Format.number(-12.5) == "-12.5")
    }

    @Test("The assembly lists each instance with its part, placement and status")
    func assembly() async throws {
        let plate = Part(name: "Plate", features: [Fixtures.box("Box", 60, 40, 5)])
        let document = CADDocument(
            parameters: [Parameter(name: "gap", expression: 10)], parts: [plate],
            assembly: Assembly(instances: [
                Instance(name: "Base", part: plate.id, grounded: true),
                Instance(
                    name: "Lid", part: plate.id, body: "Body1",
                    placement: Placement(
                        translation: Vector3(0, 0, "gap + 5"), rotationAxis: Vector3(0, 0, 1), rotationDegrees: 90)),
                Instance(name: "Ghost", part: UUID()),
            ]))
        let result = try await RebuildEngine(kernel: FakeKernel()).rebuild(document)
        let lines = DocumentListing.render(document, result: result).split(separator: "\n").map(String.init)
        let unbuilt = DocumentListing.render(document, result: nil).split(separator: "\n").map(String.init)
        let expected: [String] = [
            "assembly",
            "  Base  Plate at origin, grounded  ok",
            "  Lid  Plate/Body1 at (0, 0, gap + 5) rotated 90° about (0, 0, 1)  ok",
            "  Ghost  (missing part)  failed: its part no longer exists",
        ]

        #expect(Array(lines.suffix(4)) == expected)
        #expect(unbuilt.last == "  Ghost  (missing part)  not built")
    }

    @Test("An empty assembly says so; a document without one lists no assembly")
    func emptyAssembly() {
        let empty = CADDocument(parts: [Part(name: "P")], assembly: Assembly())

        #expect(DocumentListing.render(empty, result: nil).hasSuffix("assembly\n  (no instances)"))
        #expect(!DocumentListing.render(CADDocument(parts: [Part(name: "P")]), result: nil).contains("assembly"))
    }
}
