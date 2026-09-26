import CADModel
import Foundation

public struct BodySelector: Sendable, Equatable, CustomStringConvertible {
    public var part: String?
    public var body: String?

    public init(part: String? = nil, body: String? = nil) {
        self.part = part
        self.body = body
    }

    public var description: String {
        switch (part, body) {
        case (nil, nil): "all bodies"
        case (let part?, nil): "all bodies of \(part)"
        case (nil, let body?): body
        case (let part?, let body?): "\(part)/\(body)"
        }
    }
}

public enum FeatureType: String, Sendable, Codable, CaseIterable {
    case box, cylinder, sphere, cone, torus, boolean, transform, fillet, chamfer, shell

    public init(_ kind: FeatureKind) {
        switch kind {
        case .boolean: self = .boolean
        case .transform: self = .transform
        case .fillet: self = .fillet
        case .chamfer: self = .chamfer
        case .shell: self = .shell
        case .primitive(let primitive):
            switch primitive.shape {
            case .box: self = .box
            case .cylinder: self = .cylinder
            case .sphere: self = .sphere
            case .cone: self = .cone
            case .torus: self = .torus
            }
        }
    }
}

public enum Check: Sendable, Equatable {
    case gate
    case bodyCount(Int)
    case boundingBox(BodySelector, min: SIMD3<Double>?, max: SIMD3<Double>?, size: SIMD3<Double>?, tolerance: Double)
    case volume(BodySelector, expected: Double, tolerance: Double)
    case parameter(name: String, value: Double, tolerance: Double)
    case featureCount(FeatureType, min: Int?, max: Int?)
    case referenceIoU(threshold: Double)
    case unchangedExcept(features: [String], parameters: [String], allowNewFeatures: Bool)
}

extension Check: Decodable {
    private struct Key: CodingKey {
        let stringValue: String
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let type = try container.decode(String.self, forKey: Key("type"))
        func fail(_ reason: String) -> DecodingError {
            DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: reason))
        }
        func allow(_ keys: Set<String>) throws {
            let unknown = container.allKeys.map(\.stringValue).filter { $0 != "type" && !keys.contains($0) }.sorted()
            guard unknown.isEmpty else { throw fail("A \(type) check has no \(unknown.joined(separator: ", ")) key") }
        }
        func optional<T: Decodable>(_ key: String, _: T.Type = T.self) throws -> T? {
            try container.decodeIfPresent(T.self, forKey: Key(key))
        }
        func required<T: Decodable>(_ key: String, _: T.Type = T.self) throws -> T {
            try container.decode(T.self, forKey: Key(key))
        }
        func vector(_ key: String) throws -> SIMD3<Double>? {
            guard let values: [Double] = try optional(key) else { return nil }
            guard values.count == 3 else { throw fail("'\(key)' must be [x, y, z]") }
            return SIMD3(values[0], values[1], values[2])
        }
        func selector() throws -> BodySelector { BodySelector(part: try optional("part"), body: try optional("body")) }

        switch type {
        case "gate":
            try allow([])
            self = .gate
        case "bodyCount":
            try allow(["equals"])
            self = .bodyCount(try required("equals"))
        case "boundingBox":
            try allow(["part", "body", "min", "max", "size", "tolerance"])
            let (min, max, size) = (try vector("min"), try vector("max"), try vector("size"))
            guard min != nil || max != nil || size != nil else {
                throw fail("A boundingBox check needs min, max or size")
            }
            self = .boundingBox(
                try selector(), min: min, max: max, size: size, tolerance: try optional("tolerance") ?? 0.01)
        case "volume":
            try allow(["part", "body", "expected", "tolerance"])
            self = .volume(
                try selector(), expected: try required("expected"), tolerance: try optional("tolerance") ?? 0.005)
        case "parameter":
            try allow(["name", "value", "tolerance"])
            self = .parameter(
                name: try required("name"), value: try required("value"),
                tolerance: try optional("tolerance") ?? 1e-6)
        case "featureCount":
            try allow(["feature", "equals", "min", "max"])
            let equals: Int? = try optional("equals")
            let min = try equals ?? optional("min")
            let max = try equals ?? optional("max")
            guard min != nil || max != nil else { throw fail("A featureCount check needs equals, min or max") }
            self = .featureCount(try required("feature"), min: min, max: max)
        case "referenceIoU":
            try allow(["threshold"])
            self = .referenceIoU(threshold: try required("threshold"))
        case "unchangedExcept":
            try allow(["features", "parameters", "allowNewFeatures"])
            self = .unchangedExcept(
                features: try optional("features") ?? [], parameters: try optional("parameters") ?? [],
                allowNewFeatures: try optional("allowNewFeatures") ?? false)
        default:
            throw fail("Unknown check type '\(type)'")
        }
    }
}

extension Check: CustomStringConvertible {
    public var description: String {
        switch self {
        case .gate:
            return "gate: every feature ok, every body one valid closed solid"
        case .bodyCount(let count):
            return "body count = \(count)"
        case .boundingBox(let selector, let min, let max, let size, let tolerance):
            let parts = [
                min.map { "min \(BenchFormat.vector($0))" }, max.map { "max \(BenchFormat.vector($0))" },
                size.map { "size \(BenchFormat.vector($0))" },
            ].compactMap { $0 }
            return "bounding box of \(selector): \(parts.joined(separator: ", ")) ±\(BenchFormat.number(tolerance)) mm"
        case .volume(let selector, let expected, let tolerance):
            return "volume of \(selector) = \(BenchFormat.number(expected)) mm³ ±\(BenchFormat.percent(tolerance))"
        case .parameter(let name, let value, _):
            return "parameter \(name) = \(BenchFormat.number(value))"
        case .featureCount(let type, let min, let max):
            switch (min, max) {
            case (let min?, let max?) where min == max: return "\(type.rawValue) features = \(min)"
            case (let min?, let max?): return "\(type.rawValue) features between \(min) and \(max)"
            case (let min?, nil): return "\(type.rawValue) features ≥ \(min)"
            case (nil, let max?): return "\(type.rawValue) features ≤ \(max)"
            case (nil, nil): return "\(type.rawValue) features"
            }
        case .referenceIoU(let threshold):
            return "overlap with reference ≥ \(BenchFormat.number(threshold))"
        case .unchangedExcept(let features, let parameters, let allowNewFeatures):
            var parts: [String] = []
            if !features.isEmpty { parts.append("features \(features.joined(separator: ", "))") }
            if !parameters.isEmpty { parts.append("parameters \(parameters.joined(separator: ", "))") }
            if allowNewFeatures { parts.append("new features allowed") }
            return parts.isEmpty ? "unchanged elsewhere" : "unchanged except \(parts.joined(separator: ", "))"
        }
    }
}
