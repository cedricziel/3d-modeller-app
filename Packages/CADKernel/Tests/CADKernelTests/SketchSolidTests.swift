@testable import CADKernel
import Foundation
import Testing

private let xy = ProfilePlane(origin: .zero, xAxis: SIMD3(1, 0, 0), yAxis: SIMD3(0, 1, 0))
private let xz = ProfilePlane(origin: .zero, xAxis: SIMD3(1, 0, 0), yAxis: SIMD3(0, 0, 1))

private func polygon(_ points: [SIMD2<Double>], names: [String]) -> [ProfileCurve] {
    points.indices.map { index in
        ProfileCurve(name: names[index], geometry: .line(points[index], points[(index + 1) % points.count]))
    }
}

private func rectangle(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, prefix: String = "S.line")
    -> [ProfileCurve]
{
    polygon(
        [SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1)],
        names: (1...4).map { "\(prefix)\($0)" }
    )
}

private func volume(_ solid: Solid) throws -> Double {
    try #require(try Kernel.metrics(of: solid).volume)
}

@Suite("Solids from profiles")
struct SketchSolidTests {
    @Test("A rectangle extrudes into a box with start, end and one side per line")
    func rectangleExtrude() throws {
        let profile = Profile(plane: xy, regions: [ProfileRegion(outer: rectangle(0, 0, 60, 40), holes: [])])
        let solid = try Kernel.extrude(profile, from: 0, to: 10, feature: "F")

        #expect(try approx(volume(solid), 24000))
        let metrics = try Kernel.metrics(of: solid)
        #expect(approx(metrics.boundsMin, SIMD3(0, 0, 0)))
        #expect(approx(metrics.boundsMax, SIMD3(60, 40, 10)))
        let start = try face("F.start", in: solid)
        #expect(approx(start.normal ?? .zero, SIMD3(0, 0, -1)))
        #expect(try approx(face("F.end", in: solid).centroid.z, 10))
        for index in 1...4 {
            _ = try face("F.side[S.line\(index)]", in: solid)
        }
        #expect(try approx(face("F.side[S.line1]", in: solid).normal ?? .zero, SIMD3(0, -1, 0)))
    }

    @Test("A circle inside the outline becomes a hole named after the circle")
    func plateWithHole() throws {
        let hole = [ProfileCurve(name: "S.circle1", geometry: .circle(center: SIMD2(30, 20), radius: 5))]
        let profile = Profile(plane: xy, regions: [ProfileRegion(outer: rectangle(0, 0, 60, 40), holes: [hole])])
        let solid = try Kernel.extrude(profile, from: 0, to: 10, feature: "F")

        let expected: Double = 24000 - Double.pi * 25 * 10
        #expect(try approx(volume(solid), expected))
        let side = try face("F.side[S.circle1]", in: solid)
        #expect(side.surface == .cylinder)
        #expect(approx(side.radius, 5))
    }

    @Test("Offsets follow the plane normal; on XZ the normal is -Y")
    func reversedAndOffset() throws {
        let profile = Profile(plane: xz, regions: [ProfileRegion(outer: rectangle(0, 0, 10, 10), holes: [])])
        let solid = try Kernel.extrude(profile, from: -5, to: 5, feature: "F")

        let metrics = try Kernel.metrics(of: solid)
        #expect(approx(metrics.boundsMin.y, -5))
        #expect(approx(metrics.boundsMax.y, 5))
        #expect(try approx(face("F.start", in: solid).centroid.y, 5))
        #expect(try approx(face("F.end", in: solid).centroid.y, -5))
    }

    @Test("A slot of lines and arcs names its round ends after the arcs")
    func arcSlot() throws {
        let curves = [
            ProfileCurve(name: "S.line1", geometry: .line(SIMD2(0, -4), SIMD2(20, -4))),
            ProfileCurve(
                name: "S.arc1",
                geometry: .arc(
                    center: SIMD2(20, 0), radius: 4, start: SIMD2(20, -4), mid: SIMD2(24, 0), end: SIMD2(20, 4))
            ),
            ProfileCurve(name: "S.line2", geometry: .line(SIMD2(20, 4), SIMD2(0, 4))),
            ProfileCurve(
                name: "S.arc2",
                geometry: .arc(center: SIMD2(0, 0), radius: 4, start: SIMD2(0, 4), mid: SIMD2(-4, 0), end: SIMD2(0, -4))
            ),
        ]
        let solid = try Kernel.extrude(
            Profile(plane: xy, regions: [ProfileRegion(outer: curves, holes: [])]), from: 0, to: 3, feature: "F"
        )

        let expected: Double = (20 * 8 + Double.pi * 16) * 3
        #expect(try approx(volume(solid), expected))
        #expect(try face("F.side[S.arc1]", in: solid).surface == .cylinder)
        #expect(try face("F.side[S.arc2]", in: solid).surface == .cylinder)
        #expect(!names(solid).contains { $0.contains(".face[") })
    }

    @Test("A cup section revolved fully about Z has sides but no caps")
    func revolveCupProfile() throws {
        let section = polygon(
            [SIMD2(0, 0), SIMD2(30, 0), SIMD2(30, 50), SIMD2(27, 50), SIMD2(27, 4), SIMD2(0, 4)],
            names: (1...6).map { "S.line\($0)" }
        )
        let solid = try Kernel.revolve(
            Profile(plane: xz, regions: [ProfileRegion(outer: section, holes: [])]), axisOrigin: .zero,
            axisDirection: SIMD3(0, 0, 1), angle: 2 * .pi, feature: "R"
        )

        let expected = Double.pi * (900 * 50 - 729 * 46)
        #expect(try approx(volume(solid), expected))
        let outer = try face("R.side[S.line2]", in: solid)
        #expect(outer.surface == .cylinder)
        #expect(approx(outer.radius, 30))
        let described = try Kernel.topology(of: solid).faces.map { "\($0.names) \($0.surface) \($0.centroid)" }
        #expect(!names(solid).contains { $0.contains(".face[") }, "\(described)")
        #expect(!names(solid).contains("R.start"))
        #expect(!names(solid).contains("R.end"))
    }

    @Test("A partial revolution has a start and an end cap")
    func partialRevolve() throws {
        let profile = Profile(plane: xz, regions: [ProfileRegion(outer: rectangle(20, 0, 30, 10), holes: [])])
        let solid = try Kernel.revolve(
            profile, axisOrigin: .zero, axisDirection: SIMD3(0, 0, 1), angle: .pi / 2, feature: "R"
        )

        let expected = Double.pi / 4 * (900 - 400) * 10
        #expect(try approx(volume(solid), expected))
        #expect(try approx(face("R.start", in: solid).centroid.y, 0))
        #expect(try approx(face("R.end", in: solid).centroid.x, 0, tolerance: 1e-6))
    }

    @Test("Disjoint regions give one value with several solids")
    func twoRegions() throws {
        let profile = Profile(
            plane: xy,
            regions: [
                ProfileRegion(outer: rectangle(0, 0, 10, 10), holes: []),
                ProfileRegion(outer: rectangle(20, 0, 30, 10, prefix: "S.l"), holes: []),
            ]
        )
        let solid = try Kernel.extrude(profile, from: 0, to: 1, feature: "F")

        #expect(try Kernel.metrics(of: solid).solidCount == 2)
        #expect(solid.faceNames.filter { $0.contains("F.start") }.count == 2)
        #expect(try approx(volume(solid), 200))
    }

    @Test("Overlapping regions fuse into one solid instead of overlapping solids")
    func overlappingRegions() throws {
        let circle = [ProfileCurve(name: "S.circle1", geometry: .circle(center: SIMD2(10, 5), radius: 3))]
        let profile = Profile(
            plane: xy,
            regions: [
                ProfileRegion(outer: rectangle(0, 0, 10, 10), holes: []), ProfileRegion(outer: circle, holes: []),
            ])
        let solid = try Kernel.extrude(profile, from: 0, to: 2, feature: "F")

        #expect(try Kernel.metrics(of: solid).solidCount == 1)
        let expected: Double = (100 + 4.5 * Double.pi) * 2
        #expect(approx(try volume(solid), expected))
        #expect(names(solid).contains("F.side[S.circle1]"))
        #expect(names(solid).contains("F.side[S.line1]"))
    }

    @Test("Degenerate inputs are refused")
    func invalidInputs() throws {
        let square = Profile(plane: xy, regions: [ProfileRegion(outer: rectangle(0, 0, 1, 1), holes: [])])
        let empty = Profile(plane: xy, regions: [])
        #expect(throws: KernelError.self) { try Kernel.extrude(empty, from: 0, to: 1, feature: "F") }
        #expect(throws: KernelError.self) { try Kernel.extrude(square, from: 1, to: 1, feature: "F") }
        #expect(throws: KernelError.self) { try Kernel.extrude(square, from: 0, to: .nan, feature: "F") }
        let axis = SIMD3<Double>(0, 1, 0)
        #expect(throws: KernelError.self) {
            try Kernel.revolve(square, axisOrigin: SIMD3(-1, 0, 0), axisDirection: axis, angle: 0, feature: "R")
        }
        #expect(throws: KernelError.self) {
            try Kernel.revolve(square, axisOrigin: SIMD3(-1, 0, 0), axisDirection: axis, angle: 7, feature: "R")
        }
        #expect(throws: KernelError.self) {
            try Kernel.revolve(square, axisOrigin: .zero, axisDirection: .zero, angle: 1, feature: "R")
        }
    }
}
