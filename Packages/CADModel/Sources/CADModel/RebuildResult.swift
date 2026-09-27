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
    case reference(String)
    case sketch(String)
    case extent(String)
    case kernel(String)

    public var description: String {
        switch self {
        case .expression(let field, let error): "\(field): \(error)"
        case .duplicateName(let name): "another feature in this part is already named '\(name)'"
        case .unknownBody(let name): "no body named '\(name)' exists at this point"
        case .bodyConsumed(let name, let feature): "\(name) was used up as a tool by \(feature)"
        case .invalidTools(let detail): detail
        case .reference(let detail): detail
        case .sketch(let detail): detail
        case .extent(let detail): detail
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
    public let topology: BodyTopology?
    public let error: String?
}

public struct PartResult: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let features: [FeatureResult]
    public let bodies: [BodyResult]
    public let sketches: [SketchResult]
    public let appearance: Appearance?
}

public struct RebuildResult: Sendable, Equatable {
    public let parameters: ParameterTable
    public let parts: [PartResult]
    /// The placed instances; nil when the document has no assembly.
    public let assembly: AssemblyResult?

    public var bodies: [BodyResult] { parts.flatMap(\.bodies) }
    public var triangleCount: Int { bodies.reduce(0) { $0 + ($1.mesh?.triangleCount ?? 0) } }
    public var failedFeatureCount: Int {
        parts.flatMap(\.features).count { if case .failed = $0.status { true } else { false } }
    }

    public var failedInstanceCount: Int {
        (assembly?.instances ?? []).count { $0.status != .ok }
    }

    public var failedJointCount: Int {
        (assembly?.joints ?? []).count { !$0.status.holds }
    }

    public func feature(id: UUID) -> FeatureResult? {
        parts.lazy.flatMap(\.features).first { $0.id == id }
    }

    public func sketch(id: UUID) -> SketchResult? {
        parts.lazy.flatMap(\.sketches).first { $0.id == id }
    }
}
