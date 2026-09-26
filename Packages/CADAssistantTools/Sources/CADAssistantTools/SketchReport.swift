import CADModel
import Foundation

/// The get_sketch text: frame, state, entities with solved coordinates, constraints, open ends.
enum SketchReport {
    static func render(_ feature: Feature, result: RebuildResult?) -> String {
        guard case .sketch(let sketch) = feature.kind else { return "\(feature.name) is not a sketch." }
        let plane = DocumentListing.planeText(sketch.plane)
        var lines: [String] = []
        let solved = result?.sketch(id: feature.id)
        if let solved {
            let frame = solved.frame
            lines.append(
                "\(feature.name) on \(plane) (origin \(Format.point(frame.origin)), x \(Format.point(frame.xAxis)), "
                    + "y \(Format.point(frame.yAxis))): \(solved.state); "
                    + DocumentListing.regionText(solved.profiles))
        } else {
            let status = result?.feature(id: feature.id)?.status.description ?? "not built"
            lines.append("\(feature.name) on \(plane): not solved (\(status)); stored starting geometry:")
        }
        let parameters = result?.parameters ?? ParameterTable([])
        lines.append("entities:")
        lines += (solved?.entities ?? sketch.entities).map { "  " + entity($0) }
        if !sketch.constraints.isEmpty {
            lines.append("constraints:")
            lines += sketch.constraints.map { "  " + constraint($0, parameters) }
        }
        if let solved {
            if !solved.profiles.openEnds.isEmpty {
                lines.append("open ends: \(solved.profiles.openEnds.joined(separator: ", "))")
            }
            if !solved.profiles.branchPoints.isEmpty {
                lines.append(
                    "ambiguous where 3 or more curves meet: \(solved.profiles.branchPoints.joined(separator: "; "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func point(_ p: SketchPoint2) -> String { "(\(Format.number(p.x)), \(Format.number(p.y)))" }

    static func entity(_ entity: SketchEntity) -> String {
        let text: String
        switch entity.geometry {
        case .point(let at): text = "point \(point(at))"
        case .line(let start, let end): text = "line \(point(start)) to \(point(end))"
        case .circle(let center, let radius): text = "circle centre \(point(center)) r=\(Format.number(radius))"
        case .arc(let center, let radius, let start, let end):
            func on(_ degrees: Double) -> SketchPoint2 {
                let angle = degrees * .pi / 180
                return SketchPoint2(center.x + radius * cos(angle), center.y + radius * sin(angle))
            }
            text =
                "arc centre \(point(center)) r=\(Format.number(radius)) from \(Format.number(start))° to "
                + "\(Format.number(end))°, \(point(on(start))) to \(point(on(end)))"
        }
        return "\(entity.name)  \(text)" + (entity.construction ? "  construction" : "")
    }

    static func constraint(_ constraint: SketchConstraint, _ parameters: ParameterTable) -> String {
        var text =
            "\(constraint.name)  \(constraint.kind.rawValue) "
            + (constraint.points + constraint.entities).joined(separator: ", ")
        if let value = constraint.value {
            let unit = constraint.kind == .angle ? "°" : ""
            switch value {
            case .number: text += " = \(value)\(unit)"
            case .expression:
                let evaluated = (try? parameters.evaluate(value)).map { " (\(Format.number($0))\(unit))" } ?? ""
                text += " = \(value)\(evaluated)"
            }
        }
        if let at = constraint.at, at.count == 2 { text += " at (\(at[0]), \(at[1]))" }
        return text
    }
}
