import Foundation
import Testing

@testable import CADSolvers

struct PerformanceTests {
    /// 25 rectangles of 8 × 6 (100 lines), each one's bottom-left corner on the previous one's
    /// top-right corner, the first corner fixed at the origin, drawn with every coordinate off by
    /// up to 1.5.
    static func staircase(count: Int = 25) -> Sketch {
        var entities: [SketchEntity] = []
        var constraints: [SketchConstraint] = []
        var noiseSeed = 0.0
        func noisy(_ value: Double) -> Double {
            noiseSeed += 1
            return value + 1.5 * sin(noiseSeed * 12.9898)
        }
        for k in 0..<count {
            let x = Double(k) * 8
            let y = Double(k) * 6
            let corners = [SketchPoint(x, y), SketchPoint(x + 8, y), SketchPoint(x + 8, y + 6), SketchPoint(x, y + 6)]
            let first = entities.count
            for side in 0..<4 {
                let start = corners[side]
                let end = corners[(side + 1) % 4]
                entities.append(.line(noisy(start.x), noisy(start.y), noisy(end.x), noisy(end.y)))
            }
            constraints += [
                .coincident(.end(first), .start(first + 1)),
                .coincident(.end(first + 1), .start(first + 2)),
                .coincident(.end(first + 2), .start(first + 3)),
                .coincident(.end(first + 3), .start(first)),
                .horizontal(first), .horizontal(first + 2),
                .vertical(first + 1), .vertical(first + 3),
                .distance(.start(first), .end(first), 8),
                .distance(.start(first + 1), .end(first + 1), 6),
            ]
            if k == 0 {
                entities[0].geometry = .line(start: SketchPoint(0, 0), end: SketchPoint(noisy(8), noisy(0)))
                constraints.append(.fixed(.start(0)))
            } else {
                constraints.append(.coincident(.start(first), .end(first - 3)))
            }
        }
        return Sketch(entities: entities, constraints: constraints)
    }

    @Test func hundredEntities() throws {
        let sketch = Self.staircase()
        #expect(sketch.entities.count == 100)
        let clock = ContinuousClock()
        var solution: SketchSolution?
        let elapsed = try clock.measure { solution = try SketchSolver().solve(sketch) }
        let solved = try #require(solution)
        #expect(solved.state == .fullyConstrained)
        #expect(solved.line(97).map { close($0.end, SketchPoint(200, 150)) } == true)
        #expect(elapsed < .seconds(5), "solved in \(elapsed)")
    }

    @Test func concurrentSolves() async throws {
        let sketch = Fixtures.rectangle(Fixtures.sloppyEnds)
        let expected = try SketchSolver().solve(sketch)
        let solutions = await withTaskGroup(of: SketchSolution?.self) { group in
            for _ in 0..<8 {
                group.addTask { try? SketchSolver().solve(sketch) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(solutions.count == 8)
        #expect(solutions.allSatisfy { $0 == expected })
    }
}
