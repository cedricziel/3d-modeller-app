import Foundation
import Testing

@testable import CADKernel

@Suite("Topology")
struct TopologyTests {
    @Test("Box faces report plane, centroid, normal and area")
    func boxFaces() throws {
        let top = try face("B.top", in: try Kernel.box(width: 10, depth: 20, height: 30, feature: "B"))

        #expect(top.surface == .plane)
        #expect(approx(top.centroid, SIMD3(5, 10, 30)))
        #expect(approx(top.normal ?? .zero, SIMD3(0, 0, 1)))
        #expect(approx(top.area, 200))
        #expect(top.radius == nil)
    }

    @Test("Box edges know their two faces, length and direction")
    func boxEdges() throws {
        let box = try Kernel.box(width: 10, depth: 20, height: 30, feature: "B")
        let topology = try Kernel.topology(of: box)
        let edgeNames = topology.edges.map { Set($0.faces.flatMap { topology.faces[$0].names }) }

        #expect(topology.edges.count == 12)
        let index = try #require(edgeNames.firstIndex(of: ["B.top", "B.front"]))
        let edge = topology.edges[index]
        #expect(edge.curve == .line)
        #expect(approx(edge.length, 10))
        #expect(approx(edge.midpoint, SIMD3(5, 0, 30)))
        #expect(approx(abs(edge.direction?.x ?? 0), 1))
        #expect(edge.radius == nil)
    }

    @Test("Cylinder faces and circular edges report axis, centre and radius")
    func cylinder() throws {
        let cylinder = try Kernel.cylinder(
            radius: 2, height: 5, placement: Placement(translation: SIMD3(1, 1, 0)), feature: "P")
        let topology = try Kernel.topology(of: cylinder)

        let side = try face("P.side", in: cylinder)
        #expect(side.surface == .cylinder)
        #expect(approx(side.radius ?? 0, 2))
        #expect(approx(abs(side.axis?.z ?? 0), 1))
        #expect(side.normal == nil)

        let circles = topology.edges.filter { $0.curve == .circle }
        #expect(circles.count == 2)
        let top = try #require(circles.first { ($0.center?.z ?? 0) > 1 })
        #expect(approx(top.radius ?? 0, 2))
        #expect(approx(top.center ?? .zero, SIMD3(1, 1, 5)))
        #expect(approx(abs(top.axis?.z ?? 0), 1))
        #expect(approx(top.length, 4 * .pi))
    }

    @Test("A sphere face reports its centre and radius")
    func sphere() throws {
        let ball = try face(
            "S.surface",
            in: try Kernel.sphere(radius: 3, placement: Placement(translation: SIMD3(0, 0, 7)), feature: "S"))

        #expect(ball.surface == .sphere)
        #expect(approx(ball.radius ?? 0, 3))
        #expect(approx(ball.axisOrigin ?? .zero, SIMD3(0, 0, 7)))
    }
}
