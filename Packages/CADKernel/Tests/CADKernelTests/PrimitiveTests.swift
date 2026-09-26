import Foundation
import Testing
@testable import CADKernel

@Suite("Primitive solids")
struct PrimitiveTests {
    private func expectClosed(_ metrics: SolidMetrics) {
        #expect(metrics.isValid)
        #expect(metrics.isClosed)
        #expect(metrics.solidCount == 1)
    }

    @Test("A box sits with its corner on the origin")
    func box() throws {
        let metrics = try Kernel.metrics(of: Kernel.box(width: 2, depth: 3, height: 4))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 24))
        #expect(approx(metrics.boundsMin, .zero))
        #expect(approx(metrics.boundsMax, SIMD3(2, 3, 4)))
        #expect(metrics.faceCount == 6)
        #expect(metrics.edgeCount == 12)
    }

    @Test("A cylinder stands on the XY plane along +Z")
    func cylinder() throws {
        let metrics = try Kernel.metrics(of: Kernel.cylinder(radius: 1, height: 2))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 2 * .pi))
        #expect(approx(metrics.boundsMin, SIMD3(-1, -1, 0), tolerance: 1e-4))
        #expect(approx(metrics.boundsMax, SIMD3(1, 1, 2), tolerance: 1e-4))
        #expect(metrics.faceCount == 3)
    }

    @Test("A sphere is centred on the origin")
    func sphere() throws {
        let metrics = try Kernel.metrics(of: Kernel.sphere(radius: 2))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 32 * .pi / 3))
        #expect(approx(metrics.boundsMin, SIMD3(-2, -2, -2), tolerance: 1e-4))
        #expect(approx(metrics.boundsMax, SIMD3(2, 2, 2), tolerance: 1e-4))
    }

    @Test("A cone frustum has the analytic volume")
    func frustum() throws {
        let metrics = try Kernel.metrics(of: Kernel.cone(bottomRadius: 2, topRadius: 1, height: 3))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 7 * .pi))
        #expect(approx(metrics.boundsMax.z, 3))
    }

    @Test("A cone may come to a point")
    func pointedCone() throws {
        let metrics = try Kernel.metrics(of: Kernel.cone(bottomRadius: 2, topRadius: 0, height: 3))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 4 * .pi))
        #expect(metrics.faceCount == 2)
    }

    @Test("A torus lies in the XY plane around the origin")
    func torus() throws {
        let metrics = try Kernel.metrics(of: Kernel.torus(majorRadius: 3, minorRadius: 1))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 6 * .pi * .pi))
        #expect(approx(metrics.boundsMin, SIMD3(-4, -4, -1), tolerance: 1e-4))
        #expect(approx(metrics.boundsMax, SIMD3(4, 4, 1), tolerance: 1e-4))
    }

    @Test("A placement positions the primitive")
    func placed() throws {
        let placement = Placement(translation: SIMD3(0, 0, 5), axis: SIMD3(1, 0, 0), angle: .pi / 2)
        let metrics = try Kernel.metrics(of: Kernel.cylinder(radius: 1, height: 2, placement: placement))

        #expect(approx(metrics.volume, 2 * .pi))
        #expect(approx(metrics.boundsMin, SIMD3(-1, -2, 4), tolerance: 1e-4))
        #expect(approx(metrics.boundsMax, SIMD3(1, 0, 6), tolerance: 1e-4))
    }

    @Test("Non-positive sizes are rejected", arguments: [0.0, -1.0])
    func rejectsNonPositive(value: Double) {
        #expect(throws: KernelError.self) { try Kernel.box(width: value, depth: 1, height: 1) }
        #expect(throws: KernelError.self) { try Kernel.cylinder(radius: value, height: 1) }
        #expect(throws: KernelError.self) { try Kernel.sphere(radius: value) }
        #expect(throws: KernelError.self) { try Kernel.cone(bottomRadius: 1, topRadius: 0, height: value) }
        #expect(throws: KernelError.self) { try Kernel.torus(majorRadius: 2, minorRadius: value) }
    }

    @Test("Non-finite sizes are rejected", arguments: [Double.nan, .infinity])
    func rejectsNonFinite(value: Double) {
        #expect(throws: KernelError.self) { try Kernel.box(width: 1, depth: value, height: 1) }
        #expect(throws: KernelError.self) { try Kernel.sphere(radius: value) }
        #expect(throws: KernelError.self) { try Kernel.cone(bottomRadius: value, topRadius: 0, height: 1) }
    }

    @Test("Degenerate cones are rejected", arguments: [(1.0, 1.0), (0.0, 0.0), (-1.0, 1.0)])
    func rejectsDegenerateCone(bottom: Double, top: Double) {
        #expect(throws: KernelError.self) { try Kernel.cone(bottomRadius: bottom, topRadius: top, height: 1) }
    }

    @Test("A torus whose tube reaches the axis is rejected", arguments: [2.0, 3.0])
    func rejectsSelfIntersectingTorus(minor: Double) {
        #expect(throws: KernelError.self) { try Kernel.torus(majorRadius: 2, minorRadius: minor) }
    }

    @Test("A bad placement is rejected")
    func rejectsBadPlacement() {
        #expect(throws: KernelError.invalidDimensions("rotation axis must not be zero")) {
            try Kernel.sphere(radius: 1, placement: Placement(axis: .zero))
        }
    }
}
