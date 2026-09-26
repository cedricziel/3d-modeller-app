import CADModel
import Foundation

/// A compact, deterministic text rendering of a document for the assistant. Each feature is one line so a change
/// shows up as a change to its own lines only.
public enum DocumentListing {
    public static func render(_ document: CADDocument, result: RebuildResult?) -> String {
        lines(document, result: result).joined(separator: "\n")
    }

    static func lines(_ document: CADDocument, result: RebuildResult?) -> [String] {
        [parametersLine(document.parameters)] + modelLines(document, result: result)
    }

    /// Everything after the parameters line: parts with their features, then the assembly.
    static func modelLines(_ document: CADDocument, result: RebuildResult?) -> [String] {
        var lines: [String] = []
        for part in document.parts {
            lines.append("part \(part.name)")
            if part.features.isEmpty { lines.append("  (no features)") }
            let bodies = part.affectedBodies()
            for feature in part.features {
                let status =
                    result?.feature(id: feature.id)?.status.description
                    ?? (feature.suppressed ? FeatureStatus.suppressed.description : "not built")
                let summary = summary(
                    feature.kind, body: bodies[feature.id], sketch: result?.sketch(id: feature.id))
                lines.append("  \(feature.name)  \(summary)  \(status)")
            }
        }
        return lines + AssemblyListing.lines(document, result: result)
    }

    static func parametersLine(_ parameters: [Parameter]) -> String {
        guard !parameters.isEmpty else { return "parameters: none" }
        let entries = ParameterTable(parameters).parameters.map { "\($0.name) = \(expression($0))" }
        return "parameters: " + entries.joined(separator: ", ")
    }

    /// The expression as written, with its value when it is not a plain number or its error.
    static func expression(_ parameter: EvaluatedParameter) -> String {
        switch parameter.value {
        case .failure(let error): return "\(parameter.expression) (error: \(error))"
        case .success(let value):
            guard case .expression = parameter.expression else { return parameter.expression.description }
            return "\(parameter.expression) (= \(Format.number(value)))"
        }
    }

    static func summary(_ kind: FeatureKind, body: String?, sketch sketchResult: SketchResult? = nil) -> String {
        let arrow = body.map { " → \($0)" } ?? ""
        switch kind {
        case .primitive(let primitive):
            var text = "\(shape(primitive.shape)) \(location(primitive.placement))"
            switch primitive.operation {
            case .newBody: break
            case .join(let target): text += ", join \(target)"
            case .cut(let target): text += ", cut \(target)"
            case .intersect(let target): text += ", intersect \(target)"
            }
            return text + arrow
        case .boolean(let boolean):
            let tools = boolean.tools.joined(separator: ", ")
            let text =
                switch boolean.operation {
                case .union: "union \(boolean.target) with \(tools)"
                case .subtract: "subtract \(tools) from \(boolean.target)"
                case .intersect: "intersect \(boolean.target) with \(tools)"
                }
            return text + arrow
        case .transform(let transform):
            return "transform \(transform.body) \(motion(transform.placement))" + arrow
        case .fillet(let fillet):
            return "fillet \(fillet.body) edges \(references(fillet.edges)) r=\(Format.operand(fillet.radius))" + arrow
        case .chamfer(let chamfer):
            return "chamfer \(chamfer.body) edges \(references(chamfer.edges)) d=\(Format.operand(chamfer.distance))"
                + arrow
        case .shell(let shell):
            return "shell \(shell.body) open at \(references(shell.faces)) t=\(Format.operand(shell.thickness))" + arrow
        case .sketch(let sketch):
            return sketchSummary(sketch, result: sketchResult)
        case .extrude(let extrude):
            return extrudeSummary(extrude) + arrow
        case .revolve(let revolve):
            return revolveSummary(revolve) + arrow
        }
    }

    /// Names as written, filters in quotes, separated by semicolons because edge names contain commas.
    static func references(_ references: [GeometryReference]) -> String {
        references.isEmpty ? "none" : references.map(\.description).joined(separator: "; ")
    }

    private static func shape(_ shape: PrimitiveShape) -> String {
        let o = Format.operand
        return switch shape {
        case .box(let width, let depth, let height): "box \(o(width))×\(o(depth))×\(o(height))"
        case .cylinder(let radius, let height): "cylinder r=\(o(radius)) h=\(o(height))"
        case .sphere(let radius): "sphere r=\(o(radius))"
        case .cone(let bottom, let top, let height): "cone r1=\(o(bottom)) r2=\(o(top)) h=\(o(height))"
        case .torus(let major, let minor): "torus R=\(o(major)) r=\(o(minor))"
        }
    }

    private static func isZero(_ scalar: Scalar) -> Bool { scalar == .number(0) }

    private static func isOrigin(_ vector: Vector3) -> Bool { isZero(vector.x) && isZero(vector.y) && isZero(vector.z) }

    private static func rotation(_ placement: Placement) -> String? {
        guard !isZero(placement.rotationDegrees) else { return nil }
        return "rotated \(Format.operand(placement.rotationDegrees))° about \(Format.vector(placement.rotationAxis))"
    }

    static func location(_ placement: Placement) -> String {
        let position = isOrigin(placement.translation) ? "at origin" : "at \(Format.vector(placement.translation))"
        return [position, rotation(placement)].compactMap(\.self).joined(separator: " ")
    }

    private static func motion(_ placement: Placement) -> String {
        let move = isOrigin(placement.translation) ? nil : "moved by \(Format.vector(placement.translation))"
        switch (rotation(placement), move) {
        case (nil, nil): return "unchanged"
        case (let rotation?, nil): return rotation
        case (nil, let move?): return move
        case (let rotation?, let move?): return "\(rotation), then \(move)"
        }
    }
}
