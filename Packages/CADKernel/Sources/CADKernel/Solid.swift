import OCCTSwift

public struct Solid: @unchecked Sendable {
    let shape: Shape
}

public struct SolidMetrics: Sendable, Equatable {
    public let volume: Double
    public let boundsMin: SIMD3<Double>
    public let boundsMax: SIMD3<Double>
    public let edgeCount: Int
    public let isValid: Bool
}

public enum KernelError: Error, Equatable, CustomStringConvertible {
    case invalidDimensions(String)
    case operationFailed(String)
    case noEdgesMatched

    public var description: String {
        switch self {
        case .invalidDimensions(let detail): "Invalid dimensions: \(detail)"
        case .operationFailed(let operation): "The geometry kernel could not \(operation)"
        case .noEdgesMatched: "No edges matched the selection"
        }
    }
}
