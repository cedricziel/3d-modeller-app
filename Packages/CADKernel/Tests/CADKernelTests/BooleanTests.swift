import Foundation
import Testing
@testable import CADKernel

@Suite("Booleans")
struct BooleanTests {
    @Test("Drilling a through hole removes exactly the cylinder's volume")
    func drill() throws {
        let plate = try Kernel.box(width: 4, depth: 4, height: 2)
        let drill = try Kernel.cylinder(radius: 1, height: 4, placement: Placement(translation: SIMD3(2, 2, -1)))
        let metrics = try Kernel.metrics(of: Kernel.boolean(.subtract, plate, drill))

        #expect(approx(metrics.volume, 32 - 2 * .pi))
        #expect(metrics.isClosed)
        #expect(metrics.solidCount == 1)
        #expect(metrics.faceCount == 7)
    }

    @Test("Uniting overlapping boxes counts the overlap once")
    func union() throws {
        let a = try Kernel.box(width: 2, depth: 2, height: 2)
        let b = try Kernel.box(width: 2, depth: 2, height: 2, placement: Placement(translation: SIMD3(1, 0, 0)))
        let metrics = try Kernel.metrics(of: Kernel.boolean(.union, a, b))

        #expect(approx(metrics.volume, 12))
        #expect(metrics.solidCount == 1)
        #expect(metrics.isClosed)
        #expect(approx(metrics.boundsMax, SIMD3(3, 2, 2)))
    }

    @Test("Intersecting a sphere with a slab above XY leaves a hemisphere")
    func intersect() throws {
        let ball = try Kernel.sphere(radius: 1)
        let slab = try Kernel.box(width: 4, depth: 4, height: 2, placement: Placement(translation: SIMD3(-2, -2, 0)))
        let metrics = try Kernel.metrics(of: Kernel.boolean(.intersect, ball, slab))

        #expect(approx(metrics.volume, 2 * .pi / 3))
        #expect(metrics.isClosed)
    }

    @Test("Uniting disjoint solids keeps both as separate solids")
    func disjointUnion() throws {
        let a = try Kernel.box(width: 1, depth: 1, height: 1)
        let b = try Kernel.box(width: 2, depth: 1, height: 1, placement: Placement(translation: SIMD3(5, 0, 0)))
        let united = try Kernel.boolean(.union, a, b)

        #expect(try Kernel.metrics(of: united).solidCount == 2)
        let volumes = try Kernel.solids(of: united).compactMap { try Kernel.metrics(of: $0).volume }.sorted()
        #expect(volumes.count == 2)
        #expect(approx(volumes.first, 1) && approx(volumes.last, 2))
    }

    @Test("Intersecting disjoint solids leaves nothing")
    func emptyIntersection() throws {
        let a = try Kernel.box(width: 1, depth: 1, height: 1)
        let b = try Kernel.box(width: 1, depth: 1, height: 1, placement: Placement(translation: SIMD3(5, 0, 0)))

        #expect(throws: KernelError.emptyResult) { try Kernel.boolean(.intersect, a, b) }
    }

    @Test("Subtracting an enclosing tool leaves nothing")
    func emptySubtraction() throws {
        let small = try Kernel.box(width: 1, depth: 1, height: 1)
        let big = try Kernel.box(width: 3, depth: 3, height: 3, placement: Placement(translation: SIMD3(-1, -1, -1)))

        #expect(throws: KernelError.emptyResult) { try Kernel.boolean(.subtract, small, big) }
    }

    @Test("Booleans leave their inputs untouched")
    func inputsUnchanged() throws {
        let plate = try Kernel.box(width: 4, depth: 4, height: 2)
        let drill = try Kernel.cylinder(radius: 1, height: 4, placement: Placement(translation: SIMD3(2, 2, -1)))
        _ = try Kernel.boolean(.subtract, plate, drill)

        #expect(approx(try Kernel.metrics(of: plate).volume, 32))
        #expect(approx(try Kernel.metrics(of: drill).volume, 4 * .pi))
    }

    @Test("A single solid splits into itself")
    func splitSingle() throws {
        #expect(Kernel.solids(of: try Kernel.sphere(radius: 1)).count == 1)
    }
}
