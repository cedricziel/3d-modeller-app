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

@Suite("Face names through operations")
struct OperationNamingTests {
    let plate = try! Kernel.box(width: 40, depth: 20, height: 5, feature: "Plate")

    @Test("A drilled hole keeps the plate's names and names the wall after the hole")
    func holeKeepsNames() throws {
        let drill = try Kernel.cylinder(
            radius: 2, height: 9, placement: Placement(translation: SIMD3(10, 10, -2)), feature: "Hole")
        let drilled = try Kernel.boolean(.subtract, plate, drill, feature: "Hole")

        #expect(
            names(drilled) == [
                "Plate.left", "Plate.right", "Plate.front", "Plate.back", "Plate.bottom", "Plate.top", "Hole.side",
            ])
        let top = try face("Plate.top", in: drilled)
        let area: Double = 800 - 4 * .pi
        let centroidX: Double = (800 * 20 - 4 * .pi * 10) / area
        #expect(approx(top.area, area, tolerance: 1e-4))
        #expect(approx(top.centroid.x, centroidX, tolerance: 1e-4))
        #expect(approx(try face("Hole.side", in: drilled).radius ?? 0, 2))
    }

    @Test("The overlap of two coplanar faces answers to both names, the target's first")
    func unionMergesNames() throws {
        let other = try Kernel.box(
            width: 40, depth: 20, height: 5, placement: Placement(translation: SIMD3(20, 0, 0)), feature: "Other")
        let merged = try Kernel.boolean(.union, plate, other, feature: "Join")
        let topology = try Kernel.topology(of: merged)

        let tops = topology.faces.filter { $0.names.contains("Plate.top") || $0.names.contains("Other.top") }
        #expect(Set(tops.map(\.names)) == [["Plate.top"], ["Plate.top", "Other.top"], ["Other.top"]])
        let shared = try #require(tops.first { $0.names.count == 2 })
        #expect(approx(shared.area, 400, tolerance: 1e-4))
    }

    @Test("A slot across the top splits it into two faces that keep the name")
    func namesSurviveBooleanSplit() throws {
        let slot = try Kernel.box(
            width: 4, depth: 30, height: 3, placement: Placement(translation: SIMD3(18, -5, 3)), feature: "Slot")
        let slotted = try Kernel.boolean(.subtract, plate, slot, feature: "Slot")
        let tops = try Kernel.topology(of: slotted).faces.filter { $0.names == ["Plate.top"] }

        #expect(tops.count == 2)
        #expect(names(slotted).isSuperset(of: ["Slot.left", "Slot.right", "Slot.bottom"]))
    }

    @Test("Faces no input explains are named after the feature")
    func fallbackNames() throws {
        #expect(Naming.fallback(2, feature: "F", existing: ["F.face[0]"]) == [["F.face[1]"], ["F.face[2]"]])
    }

    @Test("A transform moves the faces but keeps their names")
    func transformKeepsNames() throws {
        let moved = try Kernel.transform(
            plate, by: Placement(translation: SIMD3(0, 0, 10), axis: SIMD3(0, 0, 1), angle: .pi))

        #expect(moved.faceNames == plate.faceNames)
        #expect(approx(try face("Plate.front", in: moved).normal ?? .zero, SIMD3(0, 1, 0)))
    }

    @Test("Splitting a body into solids keeps each face's names")
    func solidsKeepNames() throws {
        let far = try Kernel.box(
            width: 5, depth: 5, height: 5, placement: Placement(translation: SIMD3(100, 0, 0)), feature: "Far")
        let pieces = Kernel.solids(of: try Kernel.boolean(.union, plate, far, feature: "Join"))

        #expect(pieces.map { names($0).sorted().first } == ["Plate.back", "Far.back"])
    }
}
