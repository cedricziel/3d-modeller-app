import Foundation
import Testing

@testable import CADKernel

func names(_ solid: Solid) -> Set<String> {
    Set(solid.faceNames.flatMap(\.self))
}

func face(_ name: String, in solid: Solid) throws -> FaceInfo {
    let matches = try Kernel.topology(of: solid).faces.filter { $0.names.contains(name) }
    return try #require(matches.count == 1 ? matches.first : nil, "\(name): \(matches.count) faces")
}

@Suite("Face names")
struct NamingTests {
    @Test("A box names its faces by role in its own frame")
    func boxRoles() throws {
        let box = try Kernel.box(width: 10, depth: 20, height: 30, feature: "Plate")

        #expect(box.faceNames.allSatisfy { $0.count == 1 })
        #expect(
            names(box) == ["Plate.left", "Plate.right", "Plate.front", "Plate.back", "Plate.bottom", "Plate.top"])
        #expect(approx(try face("Plate.top", in: box).normal ?? .zero, SIMD3(0, 0, 1)))
        #expect(approx(try face("Plate.front", in: box).normal ?? .zero, SIMD3(0, -1, 0)))
        #expect(approx(try face("Plate.left", in: box).centroid, SIMD3(0, 10, 15)))
    }

    @Test("Placement moves the faces but keeps their names")
    func placedBox() throws {
        let box = try Kernel.box(
            width: 10, depth: 20, height: 30,
            placement: Placement(translation: SIMD3(5, 0, 0), axis: SIMD3(0, 0, 1), angle: .pi / 2), feature: "B")

        #expect(approx(try face("B.front", in: box).normal ?? .zero, SIMD3(1, 0, 0)))
        #expect(approx(try face("B.top", in: box).normal ?? .zero, SIMD3(0, 0, 1)))
    }

    @Test("A cylinder has a side, a top and a bottom")
    func cylinderRoles() throws {
        let cylinder = try Kernel.cylinder(radius: 2, height: 5, feature: "Pin")

        #expect(names(cylinder) == ["Pin.side", "Pin.top", "Pin.bottom"])
        #expect(approx(try face("Pin.top", in: cylinder).centroid, SIMD3(0, 0, 5)))
    }

    @Test("A pointed cone has only a side and a bottom")
    func pointedCone() throws {
        let cone = try Kernel.cone(bottomRadius: 3, topRadius: 0, height: 4, feature: "Tip")

        #expect(names(cone) == ["Tip.side", "Tip.bottom"])
    }

    @Test("A cone standing on its point has a side and a top")
    func invertedCone() throws {
        let cone = try Kernel.cone(bottomRadius: 0, topRadius: 3, height: 4, feature: "Funnel")

        #expect(names(cone) == ["Funnel.side", "Funnel.top"])
    }

    @Test("Spheres and tori have one surface")
    func singleSurface() throws {
        #expect(names(try Kernel.sphere(radius: 2, feature: "Ball")) == ["Ball.surface"])
        #expect(names(try Kernel.torus(majorRadius: 5, minorRadius: 1, feature: "Ring")) == ["Ring.surface"])
    }
}
