import Testing
@testable import CADKernel

@Suite("Rectangle extrusion")
struct ExtrudeTests {
    @Test("Extruding a 2×1 rectangle by 0.5 gives a valid box of volume 1")
    func extrudesBox() throws {
        let solid = try Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5)
        let metrics = try Kernel.metrics(of: solid)

        #expect(metrics.isValid)
        #expect(approx(metrics.volume, 1.0, tolerance: 1e-9))
        #expect(metrics.edgeCount == 12)
    }

    @Test("The profile is centred on the origin in XY and extruded along +Z")
    func placement() throws {
        let metrics = try Kernel.metrics(of: Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5))

        let tolerance = 1e-6
        #expect(abs(metrics.boundsMin.x - -1.0) < tolerance)
        #expect(abs(metrics.boundsMin.y - -0.5) < tolerance)
        #expect(abs(metrics.boundsMin.z - 0.0) < tolerance)
        #expect(abs(metrics.boundsMax.x - 1.0) < tolerance)
        #expect(abs(metrics.boundsMax.y - 0.5) < tolerance)
        #expect(abs(metrics.boundsMax.z - 0.5) < tolerance)
    }

    @Test(
        "Non-positive dimensions are rejected",
        arguments: [
            (0.0, 1.0, 1.0), (1.0, -1.0, 1.0), (1.0, 1.0, 0.0),
        ])
    func rejectsNonPositive(width: Double, height: Double, depth: Double) {
        #expect(throws: KernelError.self) {
            try Kernel.extrudeRectangle(width: width, height: height, depth: depth)
        }
    }
}
