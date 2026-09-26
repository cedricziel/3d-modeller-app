import Foundation
import Testing

@testable import CADKernel

func edges(_ solid: Solid, where matches: (EdgeInfo) -> Bool) throws -> [Int] {
    let topology = try Kernel.topology(of: solid)
    return topology.edges.indices.filter { matches(topology.edges[$0]) }
}

func edge(between a: String, _ b: String, in solid: Solid) throws -> Int {
    let topology = try Kernel.topology(of: solid)
    let index = topology.edges.firstIndex { edge in
        Set(edge.faces.flatMap { topology.faces[$0].names }) == [a, b]
    }
    return try #require(index)
}

@Suite("Fillets")
struct FilletTests {
    let block = try! Kernel.box(width: 2, depth: 1, height: 0.5, feature: "Block")

    private func verticalEdges() throws -> [Int] {
        try edges(block) { abs($0.direction?.z ?? 0) > 0.999 }
    }

    @Test("Filleting the four vertical edges removes the corner material and names the new faces")
    func verticalEdgesRounded() throws {
        let radius = 0.1
        let vertical = try verticalEdges()
        let rounded = try Kernel.fillet(block, edges: vertical, radius: radius, feature: "Round")
        let metrics = try Kernel.metrics(of: rounded)

        let removedPerEdge = radius * radius * (1 - Double.pi / 4) * 0.5
        #expect(vertical.count == 4)
        #expect(metrics.isValid)
        let expectedVolume: Double = 1 - 4 * removedPerEdge
        #expect(approx(metrics.volume, expectedVolume))
        for index in 0..<4 {
            let face = try face("Round.face[\(index)]", in: rounded)
            #expect(face.surface == .cylinder)
            #expect(approx(face.radius ?? 0, radius))
        }
        #expect(names(rounded).isSuperset(of: ["Block.top", "Block.front", "Block.left"]))
    }

    @Test("Filleting every edge of a box, corners included, takes every edge")
    func allEdges() throws {
        let rounded = try Kernel.fillet(block, edges: Array(0..<12), radius: 0.1, feature: "Round")

        #expect(try Kernel.metrics(of: rounded).isValid)
        #expect(names(rounded).isSuperset(of: (0..<12).map { "Round.face[\($0)]" }))
    }

    @Test("An edge OCCT skips, such as a seam, fails the fillet instead of staying sharp")
    func seamSkipped() throws {
        let plate = try Kernel.box(width: 60, depth: 40, height: 10, feature: "P")
        let hole = try Kernel.cylinder(
            radius: 5, height: 20, placement: Placement(translation: SIMD3(30, 20, -5)), feature: "H")
        let drilled = try Kernel.boolean(.subtract, plate, hole, feature: "H")
        let seam = try #require(try Kernel.topology(of: drilled).edges.firstIndex { $0.faces.count == 1 })
        let front = try edge(between: "P.front", "P.top", in: drilled)

        #expect(
            throws: KernelError.operationFailed(
                "fillet edge \(seam); leave out seams and edges between smoothly joined faces")
        ) {
            try Kernel.fillet(drilled, edges: [front, seam], radius: 1, feature: "Round")
        }
    }

    @Test("Filleting leaves the input solid untouched")
    func inputUnchanged() throws {
        _ = try Kernel.fillet(block, edges: try verticalEdges(), radius: 0.1, feature: "Round")

        #expect(approx(try Kernel.metrics(of: block).volume, 1.0, tolerance: 1e-9))
    }

    @Test("A radius larger than the faces allow fails with a kernel error")
    func filletTooLarge() throws {
        #expect(throws: KernelError.self) {
            try Kernel.fillet(block, edges: try verticalEdges(), radius: 0.8, feature: "Round")
        }
    }

    @Test("Non-positive radius is rejected", arguments: [0.0, -0.1])
    func nonPositiveRadius(radius: Double) throws {
        #expect(throws: KernelError.invalidDimensions("radius must be greater than 0")) {
            try Kernel.fillet(block, edges: [0], radius: radius, feature: "Round")
        }
    }

    @Test("An empty edge list reports that nothing matched")
    func noEdges() throws {
        #expect(throws: KernelError.noEdgesMatched) {
            try Kernel.fillet(block, edges: [], radius: 0.1, feature: "Round")
        }
    }

    @Test("An edge index outside the solid is rejected")
    func edgeOutOfRange() throws {
        #expect(throws: KernelError.invalidDimensions("edge 12 does not exist; the solid has 12 edges")) {
            try Kernel.fillet(block, edges: [12], radius: 0.1, feature: "Round")
        }
    }
}

@Suite("Chamfers")
struct ChamferTests {
    @Test("Chamfering one edge of a cube cuts off a prism and names its face")
    func chamferOneEdge() throws {
        let cube = try Kernel.box(width: 10, depth: 10, height: 10, feature: "Cube")
        let edge = try edge(between: "Cube.top", "Cube.front", in: cube)
        let chamfered = try Kernel.chamfer(cube, edges: [edge], distance: 1, feature: "Bevel")

        #expect(approx(try Kernel.metrics(of: chamfered).volume, 1000 - 0.5 * 10))
        let bevel = try face("Bevel.face[0]", in: chamfered)
        #expect(bevel.surface == .plane)
        #expect(approx(bevel.normal ?? .zero, SIMD3(0, -1, 1) / 2.0.squareRoot()))
    }

    @Test("Non-positive distance is rejected")
    func nonPositiveDistance() throws {
        let cube = try Kernel.box(width: 10, depth: 10, height: 10)

        #expect(throws: KernelError.invalidDimensions("distance must be greater than 0")) {
            try Kernel.chamfer(cube, edges: [0], distance: 0, feature: "Bevel")
        }
    }
}

@Suite("Shells")
struct ShellTests {
    let box = try! Kernel.box(width: 60, depth: 40, height: 30, feature: "Box")

    private func top() throws -> Int {
        try #require(box.faceNames.firstIndex(of: ["Box.top"]))
    }

    @Test("Shelling a box open at the top keeps the wall inside the outline")
    func openTop() throws {
        let shelled = try Kernel.shell(box, removing: [try top()], thickness: 2, feature: "Hollow")
        let metrics = try Kernel.metrics(of: shelled)
        let expectedVolume: Double = 60 * 40 * 30 - 56 * 36 * 28
        let expectedTopArea: Double = 60 * 40 - 56 * 36

        #expect(metrics.isValid)
        #expect(metrics.solidCount == 1)
        #expect(approx(metrics.volume, expectedVolume, tolerance: 1e-4))
        #expect(approx(metrics.boundsMax, SIMD3(60, 40, 30), tolerance: 1e-4))
        let inner = try face("Hollow.inner[Box.front]", in: shelled)
        #expect(approx(inner.centroid.y, 2, tolerance: 1e-4))
        #expect(approx(try face("Hollow.inner[Box.bottom]", in: shelled).centroid.z, 2, tolerance: 1e-4))
        #expect(approx(try face("Box.top", in: shelled).area, expectedTopArea, tolerance: 1e-4))
    }

    @Test("A wall thicker than the box fails with a kernel error")
    func shellTooThick() throws {
        #expect(throws: KernelError.self) {
            try Kernel.shell(box, removing: [try top()], thickness: 25, feature: "Hollow")
        }
    }

    @Test("Shelling needs at least one face and a positive thickness")
    func shellArguments() throws {
        #expect(throws: KernelError.noFacesMatched) {
            try Kernel.shell(box, removing: [], thickness: 2, feature: "Hollow")
        }
        #expect(throws: KernelError.invalidDimensions("thickness must be greater than 0")) {
            try Kernel.shell(box, removing: [0], thickness: -1, feature: "Hollow")
        }
        #expect(throws: KernelError.invalidDimensions("face 6 does not exist; the solid has 6 faces")) {
            try Kernel.shell(box, removing: [6], thickness: 2, feature: "Hollow")
        }
    }
}
