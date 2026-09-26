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
        case .fillet: "Fillet"
        case .chamfer: "Chamfer"
        case .shell: "Shell"
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
        case .fillet: "rectangle.roundedtop"
        case .chamfer: "octagon"
        case .shell: "cube.transparent"
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
        case .fillet(let fillet):
            return [
                FeatureProperty(label: "Body", value: fillet.body),
                FeatureProperty(label: "Edges", value: fillet.edges.label),
                FeatureProperty(label: "Radius", value: fillet.radius.description),
            ]
        case .chamfer(let chamfer):
            return [
                FeatureProperty(label: "Body", value: chamfer.body),
                FeatureProperty(label: "Edges", value: chamfer.edges.label),
                FeatureProperty(label: "Distance", value: chamfer.distance.description),
            ]
        case .shell(let shell):
            return [
                FeatureProperty(label: "Body", value: shell.body),
                FeatureProperty(label: "Open faces", value: shell.faces.label),
                FeatureProperty(label: "Thickness", value: shell.thickness.description),
            ]
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

extension [GeometryReference] {
    var label: String { map(\.description).joined(separator: "; ") }
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
