import Foundation
import Testing
@testable import CADKernel

@Suite("Edge fillets")
struct FilletTests {
    @Test("Filleting the four vertical edges removes exactly the corner material")
    func filletVerticalEdges() throws {
        let (width, height, depth, radius) = (2.0, 1.0, 0.5, 0.1)
        let block = try Kernel.extrudeRectangle(width: width, height: height, depth: depth)

        let rounded = try Kernel.fillet(block, edges: .parallel(to: SIMD3(0, 0, 1)), radius: radius)
        let metrics = try Kernel.metrics(of: rounded)

        let removedPerEdge = radius * radius * (1 - Double.pi / 4) * depth
        let expected = width * height * depth - 4 * removedPerEdge
        #expect(metrics.isValid)
        #expect(abs(metrics.volume - expected) < 1e-6)
        #expect(metrics.edgeCount > 12)
    }

    @Test("Filleting leaves the input solid untouched")
    func inputUnchanged() throws {
        let block = try Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5)
        _ = try Kernel.fillet(block, edges: .parallel(to: SIMD3(0, 0, 1)), radius: 0.1)

        #expect(abs(try Kernel.metrics(of: block).volume - 1.0) < 1e-9)
    }

    @Test("A radius larger than half the block's width fails with a kernel error")
    func radiusTooLarge() throws {
        let block = try Kernel.extrudeRectangle(width: 1, height: 1, depth: 1)

        #expect(throws: KernelError.self) {
            try Kernel.fillet(block, edges: .parallel(to: SIMD3(0, 0, 1)), radius: 0.8)
        }
    }

    @Test("Non-positive radius is rejected", arguments: [0.0, -0.1])
    func nonPositiveRadius(radius: Double) throws {
        let block = try Kernel.extrudeRectangle(width: 1, height: 1, depth: 1)

        #expect(throws: KernelError.invalidDimensions("radius must be greater than 0")) {
            try Kernel.fillet(block, edges: .parallel(to: SIMD3(0, 0, 1)), radius: radius)
        }
    }

    @Test("A direction no edge follows reports that nothing matched")
    func noMatch() throws {
        let block = try Kernel.extrudeRectangle(width: 1, height: 1, depth: 1)
        let diagonal = SIMD3<Double>(1, 1, 1) / sqrt(3)

        #expect(throws: KernelError.noEdgesMatched) {
            try Kernel.fillet(block, edges: .parallel(to: diagonal), radius: 0.1)
        }
    }
}
