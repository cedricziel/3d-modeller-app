import CADModel
import Foundation

struct FakeBody: Sendable {
    var volume: Double
    var boundsMin: SIMD3<Double>
    var boundsMax: SIMD3<Double>
}

struct FakeKernelError: Error, CustomStringConvertible {
    let description: String
}

/// Boxes have exact volumes and bounds; everything else is approximate but deterministic.
struct FakeKernel: GeometryKernel {
    var onBox: @Sendable () -> Void = {}

    private func positive(_ values: Double...) throws {
        guard values.allSatisfy({ $0 > 0 }) else { throw FakeKernelError(description: "dimensions must be positive") }
    }

    private func body(volume: Double, size: SIMD3<Double>, at placement: ResolvedPlacement) -> FakeBody {
        FakeBody(volume: volume, boundsMin: placement.translation, boundsMax: placement.translation + size)
    }

    func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody {
        onBox()
        try positive(width, depth, height)
        return body(volume: width * depth * height, size: SIMD3(width, depth, height), at: placement)
    }

    func cylinder(radius: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody {
        try positive(radius, height)
        return body(volume: 3 * radius * radius * height, size: SIMD3(2 * radius, 2 * radius, height), at: placement)
    }

    func sphere(radius: Double, placement: ResolvedPlacement) throws -> FakeBody {
        try positive(radius)
        return body(volume: 4 * radius * radius * radius, size: SIMD3(repeating: 2 * radius), at: placement)
    }

    func cone(bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody
    {
        guard bottomRadius != topRadius else { throw FakeKernelError(description: "cone radii must differ") }
        return body(volume: height, size: SIMD3(1, 1, height), at: placement)
    }

    func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement) throws -> FakeBody {
        try positive(majorRadius, minorRadius)
        return body(volume: majorRadius * minorRadius, size: SIMD3(1, 1, 1), at: placement)
    }

    func boolean(_ operation: BooleanOperation, _ target: FakeBody, _ tool: FakeBody) throws -> FakeBody {
        var result = target
        switch operation {
        case .union:
            result.volume += tool.volume
            result.boundsMin = pointwiseMin(target.boundsMin, tool.boundsMin)
            result.boundsMax = pointwiseMax(target.boundsMax, tool.boundsMax)
        case .subtract: result.volume -= tool.volume
        case .intersect: result.volume = min(target.volume, tool.volume)
        }
        guard result.volume > 0 else { throw FakeKernelError(description: "the operation left no solid") }
        return result
    }

    func transform(_ body: FakeBody, by placement: ResolvedPlacement) throws -> FakeBody {
        FakeBody(
            volume: body.volume, boundsMin: body.boundsMin + placement.translation,
            boundsMax: body.boundsMax + placement.translation)
    }

    func metrics(of body: FakeBody) throws -> BodyMetrics {
        BodyMetrics(
            volume: body.volume, boundsMin: body.boundsMin, boundsMax: body.boundsMax, faceCount: 6, solidCount: 1,
            isValid: true, isClosed: true)
    }

    func mesh(of _: FakeBody) throws -> BodyMesh {
        BodyMesh(positions: [.zero, SIMD3(1, 0, 0), SIMD3(0, 1, 0)], normals: [], indices: [0, 1, 2])
    }
}
