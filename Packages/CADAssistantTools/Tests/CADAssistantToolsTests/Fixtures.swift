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
}
