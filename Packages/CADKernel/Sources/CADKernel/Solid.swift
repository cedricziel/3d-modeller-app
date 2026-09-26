import OCCTSwift

public struct Solid: @unchecked Sendable {
    let shape: Shape
    /// The names of each face, in the order of `shape.subShapes(ofType: .face)`; the first name is the primary one.
    public let faceNames: [[String]]

    init(shape: Shape, faceNames: [[String]]) {
        self.shape = shape
        self.faceNames = faceNames
    }

    init(shape: Shape, feature: String) {
        self.init(shape: shape, faceNames: Naming.fallback(shape.subShapes(ofType: .face).count, feature: feature))
    }
}

public struct SolidMetrics: Sendable, Equatable {
    public let volume: Double?
    public let boundsMin: SIMD3<Double>
    public let boundsMax: SIMD3<Double>
    public let faceCount: Int
    public let edgeCount: Int
    public let solidCount: Int
    public let isValid: Bool
    public let isClosed: Bool
}

public enum KernelError: Error, Equatable, CustomStringConvertible {
    case invalidDimensions(String)
    case operationFailed(String)
    case noEdgesMatched
    case noFacesMatched
    case emptyResult

    public var description: String {
        switch self {
        case .invalidDimensions(let detail): "Invalid dimensions: \(detail)"
        case .operationFailed(let operation): "The geometry kernel could not \(operation)"
        case .noEdgesMatched: "No edges matched the selection"
        case .noFacesMatched: "No faces matched the selection"
        case .emptyResult: "The operation left no solid"
        }
    }
}
