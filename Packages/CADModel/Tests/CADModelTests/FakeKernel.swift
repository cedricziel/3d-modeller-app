import CADModel
import Foundation
import Synchronization

struct FakeBody: Sendable, Equatable {
    var volume: Double
}

struct FakeKernelError: Error, CustomStringConvertible {
    let description: String
}

final class FakeKernel: GeometryKernel {
    private let log = Mutex<[String]>([])
    private let mainThreadCalls = Mutex(0)
    let onCall: @Sendable (String) -> Void

    init(onCall: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onCall = onCall
    }

    var calls: [String] {
        log.withLock { $0 }
    }

    var callsOnMainThread: Int {
        mainThreadCalls.withLock { $0 }
    }

    private func record(_ call: String) {
        log.withLock { $0.append(call) }
        if Thread.isMainThread {
            mainThreadCalls.withLock { $0 += 1 }
        }
        onCall(call)
    }

    private static func text(_ p: ResolvedPlacement) -> String {
        let t = p.translation
        let a = p.rotationAxis
        return "@(\(Scalar.number(t.x)),\(Scalar.number(t.y)),\(Scalar.number(t.z)))"
            + " \(Scalar.number(p.rotationDegrees))°(\(Scalar.number(a.x)),\(Scalar.number(a.y)),\(Scalar.number(a.z)))"
    }

    private static func requirePositive(_ values: Double...) throws {
        guard values.allSatisfy({ $0 > 0 }) else { throw FakeKernelError(description: "dimensions must be positive") }
    }

    func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody {
        record("box \(Scalar.number(width))x\(Scalar.number(depth))x\(Scalar.number(height)) \(Self.text(placement))")
        try Self.requirePositive(width, depth, height)
        return FakeBody(volume: width * depth * height)
    }

    func cylinder(radius: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody {
        record("cylinder r\(Scalar.number(radius)) h\(Scalar.number(height)) \(Self.text(placement))")
        try Self.requirePositive(radius, height)
        return FakeBody(volume: 100 * radius * radius * height)
    }

    func sphere(radius: Double, placement _: ResolvedPlacement) throws -> FakeBody {
        record("sphere r\(Scalar.number(radius))")
        try Self.requirePositive(radius)
        return FakeBody(volume: 1000 * radius)
    }

    func cone(bottomRadius: Double, topRadius: Double, height: Double, placement _: ResolvedPlacement) throws
        -> FakeBody
    {
        record("cone")
        guard bottomRadius != topRadius else { throw FakeKernelError(description: "cone radii must differ") }
        return FakeBody(volume: height)
    }

    func torus(majorRadius: Double, minorRadius: Double, placement _: ResolvedPlacement) throws -> FakeBody {
        record("torus")
        return FakeBody(volume: majorRadius * minorRadius)
    }

    func boolean(_ operation: BooleanOperation, _ target: FakeBody, _ tool: FakeBody) throws -> FakeBody {
        record("\(operation.rawValue) \(Scalar.number(target.volume)) \(Scalar.number(tool.volume))")
        let volume =
            switch operation {
            case .union: target.volume + tool.volume
            case .subtract: target.volume - tool.volume
            case .intersect: min(target.volume, tool.volume)
            }
        guard volume > 0 else { throw FakeKernelError(description: "The operation left no solid") }
        return FakeBody(volume: volume)
    }

    func transform(_ body: FakeBody, by placement: ResolvedPlacement) throws -> FakeBody {
        record("transform \(Scalar.number(body.volume)) \(Self.text(placement))")
        return body
    }

    func metrics(of body: FakeBody) throws -> BodyMetrics {
        BodyMetrics(
            volume: body.volume, boundsMin: .zero, boundsMax: SIMD3(1, 1, 1),
            faceCount: 6, solidCount: 1, isValid: true, isClosed: true
        )
    }

    func mesh(of _: FakeBody) throws -> BodyMesh {
        onCall("mesh")
        return BodyMesh(
            positions: [.zero, SIMD3(1, 0, 0), SIMD3(0, 1, 0)], normals: Array(repeating: SIMD3(0, 0, 1), count: 3),
            indices: [0, 1, 2]
        )
    }
}
