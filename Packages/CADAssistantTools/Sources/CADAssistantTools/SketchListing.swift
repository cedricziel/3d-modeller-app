import CADModel

extension DocumentListing {
    static func sketchSummary(_ sketch: SketchFeature, result: SketchResult?) -> String {
        var counts: [String] = []
        for kind in ["line", "arc", "circle", "point"] {
            let count = sketch.entities.count { $0.geometry.typeName == kind }
            if count > 0 { counts.append("\(count) \(kind)\(count == 1 ? "" : "s")") }
        }
        if counts.isEmpty { counts.append("empty") }
        counts.append("\(sketch.constraints.count) constraint\(sketch.constraints.count == 1 ? "" : "s")")
        var text = "on \(planeText(sketch.plane)): \(counts.joined(separator: ", "))"
        if let result {
            text += "; \(regionText(result.profiles)); \(result.state)"
        }
        return text
    }

    static func planeText(_ plane: SketchPlane) -> String {
        let offset = plane.offset == .number(0) ? "" : ", offset \(Format.operand(plane.offset))"
        return switch plane {
        case .base(let base, _): base.rawValue + offset
        case .face(let body, let face, _): "\(face) of \(body)" + offset
        }
    }

    static func regionText(_ profiles: SketchProfiles) -> String {
        guard let regions = try? profiles.regions(selecting: []) else {
            return profiles.branchPoints.isEmpty ? "no closed profile" : "ambiguous profile"
        }
        return "\(regions.count) region\(regions.count == 1 ? "" : "s")"
    }

    static func extrudeSummary(_ extrude: ExtrudeFeature) -> String {
        var text = "extrude \(extrude.sketch)"
        if !extrude.regions.isEmpty { text += " regions \(extrude.regions.joined(separator: ", "))" }
        switch extrude.extent {
        case .distance(let value): text += " \(Format.operand(value))" + (extrude.reversed ? " reversed" : "")
        case .symmetric(let value): text += " symmetric \(Format.operand(value))"
        case .throughAll: text += " through all"
        case .upToFace(let body, let face): text += " up to \(face) of \(body)"
        }
        return text + operationText(extrude.operation)
    }

    static func revolveSummary(_ revolve: RevolveFeature) -> String {
        var text = "revolve \(revolve.sketch)"
        if !revolve.regions.isEmpty { text += " regions \(revolve.regions.joined(separator: ", "))" }
        let axis =
            switch revolve.axis {
            case .sketchLine(let line): line
            case .x: "X"
            case .y: "Y"
            case .z: "Z"
            case .edge(let body, let edge): "\(edge) of \(body)"
            }
        return text + " about \(axis) \(Format.operand(revolve.angle))°" + operationText(revolve.operation)
    }

    static func operationText(_ operation: SolidOperation) -> String {
        switch operation {
        case .newBody: ""
        case .join(let target): ", join \(target)"
        case .cut(let target): ", cut \(target)"
        case .intersect(let target): ", intersect \(target)"
        }
    }
}
