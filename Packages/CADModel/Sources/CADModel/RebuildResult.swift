import Foundation

public enum FeatureStatus: Sendable, Equatable, CustomStringConvertible {
    case ok
    case failed(FeatureError)
    case skipped(dependsOn: String)
    case suppressed

    public var description: String {
        switch self {
        case .ok: "ok"
        case .failed(let error): "failed: \(error)"
        case .skipped(let dependency): "skipped: depends on \(dependency)"
        case .suppressed: "suppressed"
        }
    }
}

public enum FeatureError: Error, Sendable, Equatable, CustomStringConvertible {
    case expression(field: String, ExpressionError)
    case duplicateName(String)
    case unknownBody(String)
    case bodyConsumed(String, by: String)
    case invalidTools(String)
    case kernel(String)

    public var description: String {
        switch self {
        case .expression(let field, let error): "\(field): \(error)"
        case .duplicateName(let name): "another feature in this part is already named '\(name)'"
        case .unknownBody(let name): "no body named '\(name)' exists at this point"
        case .bodyConsumed(let name, let feature): "\(name) was used up as a tool by \(feature)"
        case .invalidTools(let detail): detail
        case .kernel(let detail): detail
        }
    }
}

public struct FeatureResult: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let status: FeatureStatus
    public let body: String?
}

public struct BodyResult: Sendable, Equatable {
    public let name: String
    public let metrics: BodyMetrics?
    public let mesh: BodyMesh?
    public let error: String?
}

public struct PartResult: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let features: [FeatureResult]
    public let bodies: [BodyResult]
}

public struct RebuildResult: Sendable, Equatable {
    public let parameters: ParameterTable
    public let parts: [PartResult]

    public var bodies: [BodyResult] { parts.flatMap(\.bodies) }
    public var triangleCount: Int { bodies.reduce(0) { $0 + ($1.mesh?.triangleCount ?? 0) } }
    public var failedFeatureCount: Int {
        parts.flatMap(\.features).count { if case .failed = $0.status { true } else { false } }
    }

    public func feature(id: UUID) -> FeatureResult? {
        parts.lazy.flatMap(\.features).first { $0.id == id }
    }
}
