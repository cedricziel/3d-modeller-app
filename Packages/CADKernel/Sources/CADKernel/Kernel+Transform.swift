import OCCTSwift
import simd

extension Kernel {
    public static func transform(_ solid: Solid, by placement: Placement) throws -> Solid {
        try validate(placement)
        return try OCCTSerial.withLock { Solid(shape: try placed(solid.shape, placement)) }
    }

    static func validate(_ placement: Placement) throws {
        let values = [placement.translation, placement.axis].flatMap { [$0.x, $0.y, $0.z] } + [placement.angle]
        guard values.allSatisfy(\.isFinite) else {
            throw KernelError.invalidDimensions("placement values must be finite")
        }
        guard placement.largestAxisComponent > 0 else {
            throw KernelError.invalidDimensions("rotation axis must not be zero")
        }
    }

    static func placed(_ shape: Shape, _ placement: Placement) throws -> Shape {
        let r = placement.rotation
        let t = placement.translation
        guard
            let matrix = Matrix12Grouped([
                r[0][0], r[1][0], r[2][0],
                r[0][1], r[1][1], r[2][1],
                r[0][2], r[1][2], r[2][2],
                t.x, t.y, t.z,
            ]),
            let moved = shape.transformed(matrix: matrix),
            moved.isValid
        else {
            throw KernelError.operationFailed("apply the placement")
        }
        return moved
    }
}
