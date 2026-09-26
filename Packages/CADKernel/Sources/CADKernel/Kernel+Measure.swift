import OCCTSwift

/// Which part of a solid a measurement uses; indices follow `Kernel.topology(of:)`.
public enum SubShape: Sendable, Equatable {
    case whole
    case face(Int)
    case edge(Int)
}

public struct Distance: Sendable, Equatable {
    public let value: Double
    public let pointA: SIMD3<Double>
    public let pointB: SIMD3<Double>
}

extension Kernel {
    /// The minimum distance between two solids or their faces or edges; 0 when they touch or overlap.
    public static func distance(_ a: Solid, _ subA: SubShape, _ b: Solid, _ subB: SubShape) throws -> Distance {
        try OCCTSerial.withLock {
            try minimumDistance(try shape(of: a, subA), try shape(of: b, subB))
        }
    }

    public static func distance(from point: SIMD3<Double>, to solid: Solid, _ sub: SubShape) throws -> Distance {
        try OCCTSerial.withLock {
            guard let vertex = Shape.vertex(at: point) else {
                throw KernelError.operationFailed("measure the distance")
            }
            return try minimumDistance(vertex, try shape(of: solid, sub))
        }
    }

    public static func bounds(of solid: Solid, _ sub: SubShape) throws -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        try OCCTSerial.withLock {
            guard let bounds = try shape(of: solid, sub).boundingBoxOptimal() else {
                throw KernelError.operationFailed("measure the bounds")
            }
            return bounds
        }
    }

    private static func minimumDistance(_ a: Shape, _ b: Shape) throws -> Distance {
        guard let result = a.distance(to: b), result.distance.isFinite else {
            throw KernelError.operationFailed("measure the distance")
        }
        return Distance(value: result.distance, pointA: result.pointOnShape1, pointB: result.pointOnShape2)
    }

    private static func shape(of solid: Solid, _ sub: SubShape) throws -> Shape {
        switch sub {
        case .whole:
            return solid.shape
        case .face(let index):
            return try element(index, of: solid.shape.subShapes(ofType: .face), "face")
        case .edge(let index):
            return try element(index, of: solid.shape.subShapes(ofType: .edge), "edge")
        }
    }

    private static func element(_ index: Int, of shapes: [Shape], _ kind: String) throws -> Shape {
        guard shapes.indices.contains(index) else {
            throw KernelError.invalidDimensions(
                "\(kind) \(index) does not exist; the solid has \(shapes.count) \(kind)s")
        }
        return shapes[index]
    }
}
