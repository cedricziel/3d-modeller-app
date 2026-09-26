import Foundation

public struct Feature: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var suppressed: Bool
    public var kind: FeatureKind

    public init(id: UUID = UUID(), name: String, suppressed: Bool = false, kind: FeatureKind) {
        self.id = id
        self.name = name
        self.suppressed = suppressed
        self.kind = kind
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        suppressed = try container.decodeIfPresent(Bool.self, forKey: .suppressed) ?? false
        kind = try container.decode(FeatureKind.self, forKey: .kind)
    }
}

public enum FeatureKind: Sendable, Hashable {
    case primitive(PrimitiveFeature)
    case boolean(BooleanFeature)
    case transform(TransformFeature)
}

public struct PrimitiveFeature: Sendable, Hashable {
    public var shape: PrimitiveShape
    public var placement: Placement
    public var operation: SolidOperation

    public init(_ shape: PrimitiveShape, placement: Placement = .identity, operation: SolidOperation = .newBody) {
        self.shape = shape
        self.placement = placement
        self.operation = operation
    }
}

public enum PrimitiveShape: Sendable, Hashable {
    case box(width: Scalar, depth: Scalar, height: Scalar)
    case cylinder(radius: Scalar, height: Scalar)
    case sphere(radius: Scalar)
    case cone(bottomRadius: Scalar, topRadius: Scalar, height: Scalar)
    case torus(majorRadius: Scalar, minorRadius: Scalar)
}

public struct BooleanFeature: Sendable, Hashable {
    public var operation: BooleanOperation
    public var target: String
    public var tools: [String]

    public init(operation: BooleanOperation, target: String, tools: [String]) {
        self.operation = operation
        self.target = target
        self.tools = tools
    }
}

public struct TransformFeature: Sendable, Hashable {
    public var body: String
    public var placement: Placement

    public init(body: String, placement: Placement) {
        self.body = body
        self.placement = placement
    }
}

public enum BooleanOperation: String, Codable, Sendable, Hashable, CaseIterable {
    case union, subtract, intersect
}

public enum SolidOperation: Sendable, Hashable {
    case newBody
    case join(String)
    case cut(String)
    case intersect(String)

    public var targetBody: String? {
        switch self {
        case .newBody: nil
        case .join(let body), .cut(let body), .intersect(let body): body
        }
    }

    var booleanOperation: BooleanOperation? {
        switch self {
        case .newBody: nil
        case .join: .union
        case .cut: .subtract
        case .intersect: .intersect
        }
    }
}

extension FeatureKind {
    var createsNewBody: Bool {
        if case .primitive(let primitive) = self { primitive.operation == .newBody } else { false }
    }

    func affectedBody(newBody: String?) -> String? {
        switch self {
        case .primitive(let primitive): primitive.operation.targetBody ?? newBody
        case .boolean(let boolean): boolean.target
        case .transform(let transform): transform.body
        }
    }
}
