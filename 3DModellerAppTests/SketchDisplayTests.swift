import CADModel
import Foundation
import Testing
import simd

@testable import _D_Modeller

@Suite("Sketch display")
struct SketchDisplayTests {
    private func sketch(_ entities: [SketchEntity], frame: SketchFrame = .base(.xy, offset: 0)) -> SketchResult {
        SketchResult(
            id: UUID(), name: "Sketch1", frame: frame, entities: entities, state: .fullyConstrained,
            degreesOfFreedom: 0, profiles: SketchProfiles(entities))
    }

    private func line(_ name: String, _ a: (Double, Double), _ b: (Double, Double), construction: Bool = false)
        -> SketchEntity
    {
        SketchEntity(
            name: name, .line(start: SketchPoint2(a.0, a.1), end: SketchPoint2(b.0, b.1)), construction: construction)
    }

    @Test("A rectangle on XY is four segments at z = 0")
    func rectangle() {
        let segments = SketchDisplay.segments(
            of: sketch([
                line("line1", (0, 0), (60, 0)), line("line2", (60, 0), (60, 40)), line("line3", (60, 40), (0, 40)),
                line("line4", (0, 40), (0, 0)),
            ]))
        #expect(segments.count == 4)
        #expect(segments.allSatisfy { $0.start.z == 0 && $0.end.z == 0 && !$0.construction })
        #expect(segments[1].start == SIMD3(60, 0, 0))
        #expect(segments[1].end == SIMD3(60, 40, 0))
    }

    @Test("A circle on XZ lies in y = 0 and is drawn in at least 36 pieces")
    func circleOnXZ() {
        let segments = SketchDisplay.segments(
            of: sketch(
                [SketchEntity(name: "circle1", .circle(center: SketchPoint2(0, 10), radius: 5))],
                frame: .base(.xz, offset: 0)))
        #expect(segments.count >= 36)
        #expect(segments.allSatisfy { abs($0.start.y) < 1e-6 && abs($0.end.y) < 1e-6 })
        let heights = segments.map(\.start.z)
        #expect(abs((heights.max() ?? 0) - 15) < 1e-3)
    }

    @Test("Construction lines are dashed")
    func dashed() {
        let segments = SketchDisplay.segments(of: sketch([line("line1", (0, 0), (10, 0), construction: true)]))
        #expect(segments.count == 3)
        #expect(segments.allSatisfy { $0.construction })
        #expect(segments.map(\.start.x) == [0, 4, 8])
    }

    @Test("A point is a small cross")
    func point() {
        let segments = SketchDisplay.segments(of: sketch([SketchEntity(name: "point1", .point(SketchPoint2(1, 2)))]))
        #expect(segments.count == 2)
    }
}
