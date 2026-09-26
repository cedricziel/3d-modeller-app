import Foundation

extension Part {
    /// The body each `newBody` feature creates, by name: the n-th such feature owns `Body<n>`.
    public func createdBodies() -> [String: UUID] {
        var bodies: [String: UUID] = [:]
        for feature in features where feature.kind.createsNewBody {
            bodies["Body\(bodies.count + 1)"] = feature.id
        }
        return bodies
    }

    /// The body each feature creates or changes, by feature id.
    public func affectedBodies() -> [UUID: String] {
        var bodies: [UUID: String] = [:]
        var created = 0
        for feature in features {
            var newBody: String?
            if feature.kind.createsNewBody {
                created += 1
                newBody = "Body\(created)"
            }
            bodies[feature.id] = feature.kind.affectedBody(newBody: newBody)
        }
        return bodies
    }
}

extension FeatureKind {
    /// Names of the existing bodies this feature reads or changes.
    public var bodyReferences: [String] {
        switch self {
        case .primitive(let primitive): primitive.operation.targetBody.map { [$0] } ?? []
        case .boolean(let boolean): [boolean.target] + boolean.tools
        case .transform(let transform): [transform.body]
        case .fillet(let fillet): [fillet.body]
        case .chamfer(let chamfer): [chamfer.body]
        case .shell(let shell): [shell.body]
        case .sketch(let sketch):
            if case .face(let body, _, _) = sketch.plane { [body] } else { [] }
        case .extrude(let extrude):
            [extrude.operation.targetBody, extrude.extent.referenceBody].compactMap(\.self)
        case .revolve(let revolve):
            [revolve.operation.targetBody, revolve.axis.referenceBody].compactMap(\.self)
        }
    }

    public mutating func renameBodyReferences(_ rename: (String) -> String) {
        switch self {
        case .primitive(var primitive):
            primitive.operation = primitive.operation.renamingBody(rename)
            self = .primitive(primitive)
        case .sketch(var sketch):
            if case .face(let body, let face, let offset) = sketch.plane {
                sketch.plane = .face(body: rename(body), face: face, offset: offset)
            }
            self = .sketch(sketch)
        case .extrude(var extrude):
            extrude.operation = extrude.operation.renamingBody(rename)
            if case .upToFace(let body, let face) = extrude.extent {
                extrude.extent = .upToFace(body: rename(body), face: face)
            }
            self = .extrude(extrude)
        case .revolve(var revolve):
            revolve.operation = revolve.operation.renamingBody(rename)
            if case .edge(let body, let edge) = revolve.axis { revolve.axis = .edge(body: rename(body), edge: edge) }
            self = .revolve(revolve)
        case .boolean(var boolean):
            boolean.target = rename(boolean.target)
            boolean.tools = boolean.tools.map(rename)
            self = .boolean(boolean)
        case .transform(var transform):
            transform.body = rename(transform.body)
            self = .transform(transform)
        case .fillet(var fillet):
            fillet.body = rename(fillet.body)
            self = .fillet(fillet)
        case .chamfer(var chamfer):
            chamfer.body = rename(chamfer.body)
            self = .chamfer(chamfer)
        case .shell(var shell):
            shell.body = rename(shell.body)
            self = .shell(shell)
        }
    }
}

extension SolidOperation {
    func renamingBody(_ rename: (String) -> String) -> SolidOperation {
        switch self {
        case .newBody: .newBody
        case .join(let body): .join(rename(body))
        case .cut(let body): .cut(rename(body))
        case .intersect(let body): .intersect(rename(body))
        }
    }
}

extension ExtrudeExtent {
    /// The body an up-to face belongs to.
    public var referenceBody: String? {
        if case .upToFace(let body, _) = self { body } else { nil }
    }
}

extension RevolveAxis {
    /// The body an axis edge belongs to.
    public var referenceBody: String? {
        if case .edge(let body, _) = self { body } else { nil }
    }
}
