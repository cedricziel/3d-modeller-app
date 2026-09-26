import CADModel

/// Refuses an edit that leaves an expression failing that did not fail before, so a typo never reaches the model.
enum ExpressionAudit {
    struct Failure {
        let key: String
        let text: String
    }

    static func failures(in document: CADDocument) -> [Failure] {
        let table = ParameterTable(document.parameters)
        var failures: [Failure] = []
        for parameter in table.parameters {
            if case .failure(let error) = parameter.value {
                failures.append(
                    Failure(
                        key: "parameter \(parameter.name)",
                        text: "parameter \(parameter.name) = \(parameter.expression): \(error)"))
            }
        }
        for part in document.parts {
            for feature in part.features {
                for (field, scalar) in feature.kind.scalarFields {
                    do {
                        _ = try table.evaluate(scalar)
                    } catch {
                        failures.append(
                            Failure(
                                key: "\(feature.id) \(field) \(scalar)",
                                text: "\(feature.name).\(field) = \(scalar): \(error)"))
                    }
                }
            }
        }
        for instance in document.instances {
            for (field, scalar) in instance.placement.scalarFields {
                do {
                    _ = try table.evaluate(scalar)
                } catch {
                    failures.append(
                        Failure(
                            key: "instance \(instance.id) \(field) \(scalar)",
                            text: "\(instance.name).\(field) = \(scalar): \(error)"))
                }
            }
        }
        for joint in document.joints {
            for (field, scalar) in joint.scalarFields {
                do {
                    _ = try table.evaluate(scalar)
                } catch {
                    failures.append(
                        Failure(
                            key: "joint \(joint.id) \(field) \(scalar)",
                            text: "\(joint.name).\(field) = \(scalar): \(error)"))
                }
            }
        }
        return failures
    }

    static func check(before: CADDocument, after: CADDocument) throws(ToolError) {
        let known = Set(failures(in: before).map(\.key))
        let introduced = failures(in: after).filter { !known.contains($0.key) }
        guard !introduced.isEmpty else { return }
        throw ToolError(
            "Nothing changed, because these expressions would not evaluate:\n"
                + introduced.map { "  \($0.text)" }.joined(separator: "\n"))
    }
}

extension FeatureKind {
    /// Every numeric field with the name the rebuild uses in its errors.
    var scalarFields: [(String, Scalar)] {
        switch self {
        case .primitive(let primitive): primitive.shape.scalarFields + primitive.placement.scalarFields
        case .boolean: []
        case .transform(let transform): transform.placement.scalarFields
        case .fillet(let fillet): [("radius", fillet.radius)] + Self.filterFields("edges", fillet.edges)
        case .chamfer(let chamfer): [("distance", chamfer.distance)] + Self.filterFields("edges", chamfer.edges)
        case .shell(let shell): [("thickness", shell.thickness)] + Self.filterFields("faces", shell.faces)
        case .sketch(let sketch): Self.sketchFields(sketch)
        case .extrude(let extrude):
            switch extrude.extent {
            case .distance(let value), .symmetric(let value): [("extent.value", value)]
            case .throughAll, .upToFace: []
            }
        case .revolve(let revolve): [("angle", revolve.angle)]
        }
    }

    private static func sketchFields(_ sketch: SketchFeature) -> [(String, Scalar)] {
        var fields: [(String, Scalar)] = [("plane.offset", sketch.plane.offset)]
        for constraint in sketch.constraints {
            if let value = constraint.value { fields.append(("\(constraint.name).value", value)) }
            for (index, scalar) in (constraint.at ?? []).enumerated() {
                fields.append(("\(constraint.name).at[\(index)]", scalar))
            }
        }
        return fields
    }

    private static func filterFields(_ key: String, _ references: [GeometryReference]) -> [(String, Scalar)] {
        references.enumerated().flatMap { index, reference in
            reference.expressions.map { ("\(key)[\(index)] r", Scalar.expression($0)) }
        }
    }
}

extension PrimitiveShape {
    var scalarFields: [(String, Scalar)] {
        switch self {
        case .box(let width, let depth, let height): [("width", width), ("depth", depth), ("height", height)]
        case .cylinder(let radius, let height): [("radius", radius), ("height", height)]
        case .sphere(let radius): [("radius", radius)]
        case .cone(let bottom, let top, let height): [("bottomRadius", bottom), ("topRadius", top), ("height", height)]
        case .torus(let major, let minor): [("majorRadius", major), ("minorRadius", minor)]
        }
    }
}

extension Placement {
    var scalarFields: [(String, Scalar)] {
        [
            ("placement.translation.x", translation.x), ("placement.translation.y", translation.y),
            ("placement.translation.z", translation.z), ("placement.rotationAxis.x", rotationAxis.x),
            ("placement.rotationAxis.y", rotationAxis.y), ("placement.rotationAxis.z", rotationAxis.z),
            ("placement.rotationDegrees", rotationDegrees),
        ]
    }
}

extension Joint {
    var scalarFields: [(String, Scalar)] {
        let offsets = [("a", a), ("b", b)].flatMap { label, side in
            side.offset.map { offset in
                [("x", offset.x), ("y", offset.y), ("z", offset.z), ("angle", offset.angle)].map {
                    ("\(label).offset.\($0.0)", $0.1)
                }
            } ?? []
        }
        let limits = [("limits.min", limits?.min), ("limits.max", limits?.max)].compactMap { field, scalar in
            scalar.map { (field, $0) }
        }
        return offsets + limits
    }
}
