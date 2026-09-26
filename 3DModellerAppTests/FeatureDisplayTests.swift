import CADModel
import Testing
@testable import _D_Modeller

@Suite("Feature display")
struct FeatureDisplayTests {
    @Test("A box lists its dimensions by axis, its placement and its operation")
    func boxProperties() {
        let kind = FeatureKind.primitive(
            PrimitiveFeature(
                .box(width: "w", depth: 40, height: 10),
                placement: Placement(
                    translation: Vector3(1, 2, 3), rotationAxis: Vector3(0, 0, 1), rotationDegrees: 45),
                operation: .cut("Body1")))
        #expect(kind.title == "Box")
        #expect(
            kind.properties == [
                FeatureProperty(label: "Width (X)", value: "w"),
                FeatureProperty(label: "Depth (Y)", value: "40"),
                FeatureProperty(label: "Height (Z)", value: "10"),
                FeatureProperty(label: "Position", value: "1, 2, 3"),
                FeatureProperty(label: "Rotation", value: "45° about 0, 0, 1"),
                FeatureProperty(label: "Operation", value: "Cut Body1"),
            ])
    }

    @Test("Booleans and transforms list their bodies")
    func booleanAndTransform() {
        #expect(
            FeatureKind.boolean(BooleanFeature(operation: .subtract, target: "Body1", tools: ["Body2", "Body3"]))
                .properties == [
                    FeatureProperty(label: "Operation", value: "Subtract"),
                    FeatureProperty(label: "Target", value: "Body1"),
                    FeatureProperty(label: "Tools", value: "Body2, Body3"),
                ])
        #expect(
            FeatureKind.transform(TransformFeature(body: "Body2", placement: .identity)).properties == [
                FeatureProperty(label: "Body", value: "Body2"),
                FeatureProperty(label: "Position", value: "0, 0, 0"),
                FeatureProperty(label: "Rotation", value: "0° about 0, 0, 1"),
            ])
    }

    @Test(
        "Every kind has a title and a symbol",
        arguments: [
            FeatureKind.primitive(PrimitiveFeature(.sphere(radius: 1))),
            .primitive(PrimitiveFeature(.cylinder(radius: 1, height: 1))),
            .primitive(PrimitiveFeature(.cone(bottomRadius: 1, topRadius: 0, height: 1))),
            .primitive(PrimitiveFeature(.torus(majorRadius: 2, minorRadius: 1))),
        ])
    func titles(kind: FeatureKind) {
        #expect(!kind.title.isEmpty)
        #expect(!kind.symbolName.isEmpty)
    }

    @Test("Statuses map to distinct symbols")
    func statusSymbols() {
        let symbols: Set = [
            FeatureStatus.ok.symbolName, FeatureStatus.failed(.kernel("x")).symbolName,
            FeatureStatus.skipped(dependsOn: "A").symbolName, FeatureStatus.suppressed.symbolName,
        ]
        #expect(symbols.count == 4)
    }
}
