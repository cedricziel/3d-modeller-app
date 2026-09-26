import Foundation
import Testing

@testable import CADKernel

@Suite("Measure")
struct MeasureTests {
    private func cube(_ size: Double, at x: Double = 0, name: String = "C") throws -> Solid {
        try Kernel.box(
            width: size, depth: size, height: size, placement: Placement(translation: SIMD3(x, 0, 0)), feature: name)
    }

    private func faceIndex(_ name: String, in solid: Solid) throws -> Int {
        try #require(solid.faceNames.firstIndex { $0.contains(name) })
    }

    @Test("Two cubes 5 mm apart are 5 mm apart, with the closest points on the facing faces")
    func cubeGap() throws {
        let distance = try Kernel.distance(try cube(1), .whole, try cube(1, at: 6), .whole)

        #expect(approx(distance.value, 5))
        #expect(approx(distance.pointA.x, 1))
        #expect(approx(distance.pointB.x, 6))
    }

    @Test("A point above a cube's top face is measured to that face")
    func pointToFace() throws {
        let box = try cube(10)
        let top = try faceIndex("C.top", in: box)

        let distance = try Kernel.distance(from: SIMD3(5, 5, 20), to: box, .face(top))

        #expect(approx(distance.value, 10))
        #expect(approx(distance.pointB, SIMD3(5, 5, 10)))
    }

    @Test("Edges of two cubes are measured between the edges only")
    func edgeToEdge() throws {
        let a = try cube(1)
        let b = try cube(1, at: 3)
        let topology = try Kernel.topology(of: a)
        let edge = try #require(topology.edges.firstIndex { approx($0.midpoint, SIMD3(1, 0, 0.5)) })
        let other = try #require(try Kernel.topology(of: b).edges.firstIndex { approx($0.midpoint, SIMD3(3, 1, 0.5)) })

        let distance = try Kernel.distance(a, .edge(edge), b, .edge(other))

        #expect(approx(distance.value, (4.0 + 1.0).squareRoot()))
    }

    @Test("Overlapping solids are 0 apart")
    func overlap() throws {
        #expect(approx(try Kernel.distance(try cube(10), .whole, try cube(10, at: 5), .whole).value, 0))
    }

    @Test("A face's bounds span only that face")
    func faceBounds() throws {
        let box = try Kernel.box(width: 10, depth: 20, height: 30, feature: "B")
        let bounds = try Kernel.bounds(of: box, .face(try faceIndex("B.top", in: box)))

        #expect(approx(bounds.min, SIMD3(0, 0, 30), tolerance: 1e-4))
        #expect(approx(bounds.max, SIMD3(10, 20, 30), tolerance: 1e-4))
    }

    @Test("A face or edge index outside the solid is refused")
    func outOfRange() throws {
        let box = try cube(1)
        #expect(throws: KernelError.invalidDimensions("face 6 does not exist; the solid has 6 faces")) {
            try Kernel.bounds(of: box, .face(6))
        }
        #expect(throws: KernelError.invalidDimensions("edge 12 does not exist; the solid has 12 edges")) {
            try Kernel.distance(box, .edge(12), box, .whole)
        }
    }
}
