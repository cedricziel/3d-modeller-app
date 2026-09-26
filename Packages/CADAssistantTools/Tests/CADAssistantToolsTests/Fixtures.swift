import CADModel
import Foundation

enum Fixtures {
    static let plateParameters = [
        Parameter(name: "width", expression: 60),
        Parameter(name: "depth", expression: 40),
        Parameter(name: "t", expression: 10),
        Parameter(name: "hole_d", expression: 5.5),
        Parameter(name: "hole_r", expression: "hole_d / 2"),
    ]

    static func box(_ name: String, _ w: Scalar, _ d: Scalar, _ h: Scalar, _ operation: SolidOperation = .newBody)
        -> Feature
    {
        Feature(
            name: name, kind: .primitive(PrimitiveFeature(.box(width: w, depth: d, height: h), operation: operation)))
    }

    /// A plate with a hole, a suppressed pin, a failing cone, a boolean that depends on it and a move.
    static func plate() -> CADDocument {
        CADDocument(
            parameters: plateParameters,
            parts: [
                Part(
                    name: "Plate",
                    features: [
                        box("Base", "width", "depth", "t"),
                        Feature(
                            name: "Hole",
                            kind: .primitive(
                                PrimitiveFeature(
                                    .cylinder(radius: "hole_r", height: "t"),
                                    placement: Placement(translation: Vector3("width / 2", "depth / 2", 0)),
                                    operation: .cut("Body1")))),
                        Feature(
                            name: "Pin", suppressed: true,
                            kind: .primitive(
                                PrimitiveFeature(
                                    .cylinder(radius: 2, height: 5),
                                    placement: Placement(
                                        translation: Vector3(0, 0, 10), rotationAxis: Vector3(1, 0, 0),
                                        rotationDegrees: 90)))),
                        Feature(
                            name: "BadCone",
                            kind: .primitive(PrimitiveFeature(.cone(bottomRadius: 3, topRadius: 3, height: 5)))),
                        Feature(
                            name: "Merge",
                            kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: ["Body3"]))),
                        Feature(
                            name: "Move",
                            kind: .transform(
                                TransformFeature(body: "Body1", placement: Placement(translation: Vector3(10, 0, 0))))),
                    ])
            ])
    }

    /// A 60 × 40 rectangle `line1`…`line4` with a construction line `line5` along the Y axis.
    static let rectangleSketch = SketchFeature(
        plane: .base(.xy),
        entities: [
            SketchEntity(name: "line1", .line(start: SketchPoint2(0, 0), end: SketchPoint2(60, 0))),
            SketchEntity(name: "line2", .line(start: SketchPoint2(60, 0), end: SketchPoint2(60, 40))),
            SketchEntity(name: "line3", .line(start: SketchPoint2(60, 40), end: SketchPoint2(0, 40))),
            SketchEntity(name: "line4", .line(start: SketchPoint2(0, 40), end: SketchPoint2(0, 0))),
            SketchEntity(
                name: "line5", .line(start: SketchPoint2(0, 0), end: SketchPoint2(0, 10)), construction: true),
        ],
        constraints: [
            SketchConstraint(name: "c1", .horizontal, entities: ["line1"]),
            SketchConstraint(name: "c2", .distance, points: ["line1.start", "line1.end"], value: "width"),
        ])

    /// A box `Box1` (Body1) and the rectangle sketch `Sketch1`.
    static func sketched() -> CADDocument {
        CADDocument(
            parameters: plateParameters,
            parts: [
                Part(
                    name: "Plate",
                    features: [box("Box1", 60, 40, 10), Feature(name: "Sketch1", kind: .sketch(rectangleSketch))])
            ])
    }
}
