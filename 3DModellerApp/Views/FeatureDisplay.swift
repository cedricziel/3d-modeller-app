import CADModel
import SwiftUI

struct FeatureProperty: Hashable {
    let label: String
    let value: String
}

extension FeatureKind {
    var title: String {
        switch self {
        case .primitive(let primitive):
            switch primitive.shape {
            case .box: "Box"
            case .cylinder: "Cylinder"
            case .sphere: "Sphere"
            case .cone: "Cone"
            case .torus: "Torus"
            }
        case .boolean: "Boolean"
        case .transform: "Transform"
        }
    }

    var symbolName: String {
        switch self {
        case .primitive(let primitive):
            switch primitive.shape {
            case .box: "cube"
            case .cylinder: "cylinder"
            case .sphere: "circle"
            case .cone: "cone"
            case .torus: "circle.circle"
            }
        case .boolean: "square.on.square.intersection.dashed"
        case .transform: "move.3d"
        }
    }

    var properties: [FeatureProperty] {
        switch self {
        case .primitive(let primitive):
            return primitive.shape.properties + primitive.placement.properties
                + [FeatureProperty(label: "Operation", value: primitive.operation.label)]
        case .boolean(let boolean):
            return [
                FeatureProperty(label: "Operation", value: boolean.operation.rawValue.capitalized),
                FeatureProperty(label: "Target", value: boolean.target),
                FeatureProperty(label: "Tools", value: boolean.tools.joined(separator: ", ")),
            ]
        case .transform(let transform):
            return [FeatureProperty(label: "Body", value: transform.body)] + transform.placement.properties
        }
    }
}

extension PrimitiveShape {
    var properties: [FeatureProperty] {
        switch self {
        case .box(let width, let depth, let height):
            [
                .init(label: "Width (X)", value: width.description),
                .init(label: "Depth (Y)", value: depth.description),
                .init(label: "Height (Z)", value: height.description),
            ]
        case .cylinder(let radius, let height):
            [.init(label: "Radius", value: radius.description), .init(label: "Height (Z)", value: height.description)]
        case .sphere(let radius):
            [.init(label: "Radius", value: radius.description)]
        case .cone(let bottomRadius, let topRadius, let height):
            [
                .init(label: "Bottom radius", value: bottomRadius.description),
                .init(label: "Top radius", value: topRadius.description),
                .init(label: "Height (Z)", value: height.description),
            ]
        case .torus(let majorRadius, let minorRadius):
            [
                .init(label: "Major radius", value: majorRadius.description),
                .init(label: "Minor radius", value: minorRadius.description),
            ]
        }
    }
}

extension Placement {
    var properties: [FeatureProperty] {
        [
            FeatureProperty(label: "Position", value: translation.label),
            FeatureProperty(label: "Rotation", value: "\(rotationDegrees)° about \(rotationAxis.label)"),
        ]
    }
}

extension Vector3 {
    var label: String { "\(x), \(y), \(z)" }
}

extension SolidOperation {
    var label: String {
        switch self {
        case .newBody: "New body"
        case .join(let body): "Join \(body)"
        case .cut(let body): "Cut \(body)"
        case .intersect(let body): "Intersect \(body)"
        }
    }
}

extension FeatureStatus {
    var symbolName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .skipped: "arrow.uturn.down.circle"
        case .suppressed: "pause.circle"
        }
    }

    var tint: Color {
        switch self {
        case .ok: .green
        case .failed: .red
        case .skipped: .orange
        case .suppressed: .secondary
        }
    }
}
