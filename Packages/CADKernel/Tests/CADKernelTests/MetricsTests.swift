import OCCTSwift
import Testing

@testable import CADKernel

@Suite("Solid metrics")
struct MetricsTests {
    @Test("An extruded block is one closed solid with six faces")
    func closedBlock() throws {
        let metrics = try Kernel.metrics(
            of: Kernel.box(width: 2, depth: 1, height: 0.5, placement: Placement(translation: SIMD3(-1, -0.5, 0))))

        #expect(metrics.solidCount == 1)
        #expect(metrics.faceCount == 6)
        #expect(metrics.isClosed)
    }

    @Test("A solid bounded by a block missing one face is reported as not closed")
    func openShell() throws {
        let open = try OCCTSerial.withLock {
            let block = try #require(Shape.box(width: 1, height: 1, depth: 1))
            let faces = block.subShapes(ofType: .face)
            let shell = try #require(Shape.compound(Array(faces.dropFirst()))?.sewn())
            return Solid(shape: try #require(Shape.solidFromShells([shell])), feature: "Open")
        }
        let metrics = try Kernel.metrics(of: open)

        #expect(metrics.solidCount == 1)
        #expect(!metrics.isClosed)
        #expect(metrics.volume == nil)
    }
}
