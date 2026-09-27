@testable import CADModel
import Foundation
import simd
import Testing

private func line(_ name: String, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, construction: Bool = false)
    -> SketchEntity
{
    SketchEntity(name: name, .line(start: SketchPoint2(x1, y1), end: SketchPoint2(x2, y2)), construction: construction)
}

private func circle(_ name: String, _ x: Double, _ y: Double, _ r: Double) -> SketchEntity {
    SketchEntity(name: name, .circle(center: SketchPoint2(x, y), radius: r))
}

private let outline = [
    line("line1", 0, 0, 60, 0), line("line2", 60, 0, 60, 40), line("line3", 60, 40, 0, 40), line("line4", 0, 40, 0, 0),
]

private func entityNames(_ curves: [SketchCurve]) -> Set<String> {
    Set(curves.map(\.entity))
}

@Suite("Sketch profiles")
struct SketchProfilesTests {
    @Test("A rectangle is one loop at depth 0 and one region without holes")
    func rectangle() throws {
        let profiles = SketchProfiles(outline)
        #expect(profiles.loops.count == 1)
        #expect(profiles.loops[0].depth == 0)
        #expect(abs(profiles.loops[0].area - 2400) < 1e-9)
        let regions = try profiles.regions(selecting: [])
        #expect(regions.count == 1)
        #expect(entityNames(regions[0].outer) == ["line1", "line2", "line3", "line4"])
        #expect(regions[0].holes.isEmpty)
    }

    @Test("A circle inside the outline is a hole; a circle inside that is another region")
    func nesting() throws {
        let profiles = SketchProfiles(outline + [circle("circle1", 30, 20, 10), circle("circle2", 30, 20, 4)])
        #expect(profiles.loops.map(\.depth).sorted() == [0, 1, 2])
        let regions = try profiles.regions(selecting: [])
        #expect(regions.count == 2)
        let plate = try #require(regions.first { entityNames($0.outer).contains("line1") })
        #expect(plate.holes.map(entityNames) == [["circle1"]])
        let island = try #require(regions.first { entityNames($0.outer) == ["circle2"] })
        #expect(island.holes.isEmpty)
    }

    @Test("Selecting a loop by one of its entities gives that loop with the loops directly inside it")
    func selection() throws {
        let profiles = SketchProfiles(outline + [circle("circle1", 30, 20, 10), circle("circle2", 30, 20, 4)])
        let regions = try profiles.regions(selecting: ["circle1"])
        #expect(regions.count == 1)
        #expect(entityNames(regions[0].outer) == ["circle1"])
        #expect(regions[0].holes.map(entityNames) == [["circle2"]])
        #expect(try profiles.regions(selecting: ["line2", "line3"]).count == 1)
    }

    @Test("Selecting a loop and a hole inside it is refused instead of filling the hole")
    func loopAndHoleRefused() throws {
        let profiles = SketchProfiles(outline + [circle("circle1", 30, 20, 10), circle("circle2", 30, 20, 4)])
        #expect(throws: FeatureError.sketch("circle1 is a hole in the loop of line1; select either, not both")) {
            try profiles.regions(selecting: ["line1", "circle1"])
        }
        #expect(throws: FeatureError.sketch("circle2 is a hole in the loop of circle1; select either, not both")) {
            try profiles.regions(selecting: ["circle2", "circle1"])
        }
        #expect(try profiles.regions(selecting: ["line1", "circle2"]).count == 2)
    }

    @Test("Curves in any order and direction chain end to start")
    func scrambledSlot() throws {
        let entities = [
            SketchEntity(name: "arc1", .arc(center: SketchPoint2(20, 0), radius: 4, startAngle: -90, endAngle: 90)),
            line("line2", 0, 4, 20, 4),
            SketchEntity(name: "arc2", .arc(center: SketchPoint2(0, 0), radius: 4, startAngle: 90, endAngle: 270)),
            line("line1", 0, -4, 20, -4),
        ]
        let profiles = SketchProfiles(entities)
        let loop = try #require(profiles.loops.first)
        #expect(profiles.loops.count == 1)
        for (curve, next) in zip(loop.curves, loop.curves.dropFirst() + loop.curves.prefix(1)) {
            #expect(simd_distance(curve.geometry.end, next.geometry.start) < 1e-9)
        }
        let expected: Double = 20 * 8 + Double.pi * 16
        #expect(abs(loop.area - expected) < 0.1)
    }

    @Test("Construction entities and points are ignored")
    func ignoresConstruction() {
        let profiles = SketchProfiles(
            outline + [
                line("line5", 0, 0, 60, 40, construction: true),
                SketchEntity(name: "point1", .point(SketchPoint2(1, 1))),
            ]
        )
        #expect(profiles.loops.count == 1)
        #expect(profiles.branchPoints.isEmpty)
    }

    @Test("An open chain forms no loop and lists its free ends")
    func openChain() {
        let profiles = SketchProfiles(Array(outline.prefix(3)))
        #expect(profiles.loops.isEmpty)
        #expect(profiles.openEnds == ["line1.start (0, 0)", "line3.end (0, 40)"])
        #expect {
            try profiles.regions(selecting: [])
        } throws: { error in
            String(describing: error).contains("line1.start (0, 0)")
        }
    }

    @Test("Three curve ends at one point fail with the point and the entities")
    func branchNode() {
        let profiles = SketchProfiles(outline + [line("line5", 0, 0, -10, 0)])
        #expect(profiles.branchPoints == ["(0, 0): line1.start, line4.end, line5.start"])
        #expect {
            try profiles.regions(selecting: [])
        } throws: { error in
            String(describing: error).contains("(0, 0): line1.start, line4.end, line5.start")
        }
    }

    @Test("Selecting an unknown or open entity fails naming it")
    func badSelection() {
        let profiles = SketchProfiles(outline + [line("line5", 100, 0, 110, 0)])
        #expect {
            try profiles.regions(selecting: ["line5"])
        } throws: { error in String(describing: error).contains("line5 is not part of a closed loop") }
        #expect {
            try profiles.regions(selecting: ["circle9"])
        } throws: { error in String(describing: error).contains("no entity named 'circle9'") }
    }

    @Test("Ends closer than the tolerance join")
    func nearlyCoincident() {
        var entities = outline
        entities[1] = line("line2", 60.00005, 0, 60, 40)
        #expect(SketchProfiles(entities).loops.count == 1)
    }
}
