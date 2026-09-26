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
        }
    }

    public mutating func renameBodyReferences(_ rename: (String) -> String) {
        switch self {
        case .primitive(var primitive):
            switch primitive.operation {
            case .newBody: return
            case .join(let body): primitive.operation = .join(rename(body))
            case .cut(let body): primitive.operation = .cut(rename(body))
            case .intersect(let body): primitive.operation = .intersect(rename(body))
            }
            self = .primitive(primitive)
        case .boolean(var boolean):
            boolean.target = rename(boolean.target)
            boolean.tools = boolean.tools.map(rename)
            self = .boolean(boolean)
        case .transform(var transform):
            transform.body = rename(transform.body)
            self = .transform(transform)
        }
    }
}
