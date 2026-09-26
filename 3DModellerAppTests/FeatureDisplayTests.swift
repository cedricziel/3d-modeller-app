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

    @Test("Fillets, chamfers and shells list their body, references and size")
    func dressUp() {
        let fillet = FeatureKind.fillet(
            FilletFeature(body: "Body1", edges: [.name("edge(A.front, A.top)"), .filter("parallel Z")], radius: 2))
        #expect(fillet.title == "Fillet")
        #expect(
            fillet.properties == [
                FeatureProperty(label: "Body", value: "Body1"),
                FeatureProperty(label: "Edges", value: #"edge(A.front, A.top); "parallel Z""#),
                FeatureProperty(label: "Radius", value: "2"),
            ])
        #expect(
            FeatureKind.shell(ShellFeature(body: "Body1", faces: [.name("A.top")], thickness: "t")).properties.last
                == FeatureProperty(label: "Thickness", value: "t"))
        #expect(
            FeatureKind.chamfer(ChamferFeature(body: "Body1", edges: [.filter("circular")], distance: 1)).title
                == "Chamfer")
    }

    @Test("Sketches, extrudes and revolves describe their plane, source and extent")
    func sketchBased() {
        let sketch = FeatureKind.sketch(
            SketchFeature(
                plane: .face(body: "Body1", face: .name("Box1.top"), offset: 2),
                entities: [
                    SketchEntity(name: "line1", .line(start: SketchPoint2(0, 0), end: SketchPoint2(1, 0))),
                    SketchEntity(name: "line2", .line(start: SketchPoint2(1, 0), end: SketchPoint2(1, 1))),
                    SketchEntity(name: "circle1", .circle(center: SketchPoint2(0, 0), radius: 1)),
                ],
                constraints: [SketchConstraint(name: "c1", .horizontal, entities: ["line1"])]))
        #expect(sketch.title == "Sketch")
        #expect(
            sketch.properties == [
                FeatureProperty(label: "Plane", value: "Box1.top of Body1, offset 2"),
                FeatureProperty(label: "Entities", value: "2 lines, 1 circle"),
                FeatureProperty(label: "Constraints", value: "1"),
            ])
        let extrude = FeatureKind.extrude(
            ExtrudeFeature(sketch: "Sketch1", extent: .distance(10), reversed: true, operation: .cut("Body1")))
        #expect(
            extrude.properties == [
                FeatureProperty(label: "Sketch", value: "Sketch1"),
                FeatureProperty(label: "Regions", value: "All"),
                FeatureProperty(label: "Extent", value: "10, reversed"),
                FeatureProperty(label: "Operation", value: "Cut Body1"),
            ])
        let revolve = FeatureKind.revolve(RevolveFeature(sketch: "S", axis: .z, angle: 90))
        #expect(revolve.properties[2] == FeatureProperty(label: "Axis", value: "Z"))
        #expect(!revolve.symbolName.isEmpty && !extrude.symbolName.isEmpty && !sketch.symbolName.isEmpty)
    }

    @Test("Sketch entities read as one line each in the inspector")
    func entityLabels() {
        #expect(
            SketchEntity(name: "line1", .line(start: SketchPoint2(0, 0), end: SketchPoint2(60, 0.5))).label
                == "line (0, 0) to (60, 0.5)")
        #expect(
            SketchEntity(name: "arc1", .arc(center: SketchPoint2(0, 0), radius: 5, startAngle: 0, endAngle: 90)).label
                == "arc centre (0, 0) r 5, 0° to 90°")
        #expect(
            SketchEntity(name: "c", .circle(center: SketchPoint2(1, 2), radius: 3), construction: true).label
                == "circle centre (1, 2) r 3, construction")
    }
}
