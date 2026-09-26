import Foundation
import Testing
@testable import CADKernel

@Suite("Placement and transform")
struct PlacementTests {
    private func block() throws -> Solid {
        try Kernel.extrudeRectangle(width: 2, height: 4, depth: 1)
    }

    @Test("Translating moves the bounds and keeps the volume")
    func translate() throws {
        let moved = try Kernel.transform(block(), by: Placement(translation: SIMD3(10, 0, -1)))
        let metrics = try Kernel.metrics(of: moved)

        #expect(approx(metrics.boundsMin, SIMD3(9, -2, -1)))
        #expect(approx(metrics.boundsMax, SIMD3(11, 2, 0)))
        #expect(approx(metrics.volume, 8))
    }

    @Test("A quarter turn about Z swaps the X and Y extents")
    func rotate() throws {
        let turned = try Kernel.transform(block(), by: Placement(angle: .pi / 2))
        let metrics = try Kernel.metrics(of: turned)

        #expect(approx(metrics.boundsMin, SIMD3(-2, -1, 0)))
        #expect(approx(metrics.boundsMax, SIMD3(2, 1, 1)))
    }

    @Test("Rotation applies about the origin before the translation")
    func rotateThenTranslate() throws {
        let placement = Placement(translation: SIMD3(0, 0, 5), axis: SIMD3(1, 0, 0), angle: .pi / 2)
        let metrics = try Kernel.metrics(of: Kernel.transform(block(), by: placement))

        #expect(approx(metrics.boundsMin, SIMD3(-1, -1, 3)))
        #expect(approx(metrics.boundsMax, SIMD3(1, 0, 7)))
    }

    @Test("A non-unit axis is normalised")
    func nonUnitAxis() throws {
        let metrics = try Kernel.metrics(
            of: Kernel.transform(block(), by: Placement(axis: SIMD3(0, 0, 7), angle: .pi / 2)))

        #expect(approx(metrics.boundsMax, SIMD3(2, 1, 1)))
    }

    @Test("A zero rotation axis is rejected")
    func zeroAxis() throws {
        #expect(throws: KernelError.invalidDimensions("rotation axis must not be zero")) {
            try Kernel.transform(block(), by: Placement(axis: .zero, angle: 1))
        }
    }

    @Test("Non-finite placement values are rejected")
    func nonFinite() throws {
        #expect(throws: KernelError.self) {
            try Kernel.transform(block(), by: Placement(translation: SIMD3(.nan, 0, 0)))
        }
        #expect(throws: KernelError.self) {
            try Kernel.transform(block(), by: Placement(angle: .infinity))
        }
    }

    @Test("Transforming leaves the input untouched")
    func inputUnchanged() throws {
        let original = try block()
        _ = try Kernel.transform(original, by: Placement(translation: SIMD3(5, 5, 5)))

        #expect(approx(try Kernel.metrics(of: original).boundsMin, SIMD3(-1, -2, 0)))
    }

    @Test("A placement survives a JSON round trip")
    func codable() throws {
        let placement = Placement(translation: SIMD3(1, 2, 3), axis: SIMD3(0, 1, 0), angle: 0.5)
        let decoded = try JSONDecoder().decode(Placement.self, from: JSONEncoder().encode(placement))

        #expect(decoded == placement)
    }
}
