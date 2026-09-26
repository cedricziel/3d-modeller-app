import Testing

@testable import CADSolvers

struct MappingTests {
    let solver = SketchSolver()

    @Test func tangentWithTheCurveFirst() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [
                    .circle(center: SketchPoint(5, 8), radius: 10),
                    .line(-20, 0, 20, 0),
                    .line(5, -30, 5, 30, construction: true),
                ],
                constraints: [
                    .fixed(.start(1)), .fixed(.end(1)), .fixed(.start(2)), .fixed(.end(2)),
                    .pointOnLine(.center(0), line: 2), .radius(0, 10),
                    .tangent(0, 1),
                ]
            )
        )
        #expect(solution.state == .fullyConstrained)
        #expect(solution.circle(0).map { close($0.center, SketchPoint(5, 10)) } == true)
    }

    @Test func tangentArcAndCircle() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [
                    .arc(center: SketchPoint(0, 0), radius: 10, from: 0, to: 1),
                    .circle(center: SketchPoint(18, 0), radius: 5),
                    .line(-50, 0, 50, 0, construction: true),
                ],
                constraints: [
                    .fixed(.center(0)), .radius(0, 10), .radius(1, 5),
                    .fixed(.start(2)), .fixed(.end(2)), .pointOnLine(.center(1), line: 2),
                    .tangent(0, 1),
                ]
            )
        )
        #expect(solution.state == .underConstrained(dof: 2))
        #expect(solution.circle(1).map { close($0.center, SketchPoint(15, 0)) } == true)
    }

    @Test func equalCircleAndArc() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [
                    .circle(center: SketchPoint(0, 0), radius: 4),
                    .arc(center: SketchPoint(20, 0), radius: 9, from: 0, to: 1),
                ],
                constraints: [.radius(0, 4), .equal(1, 0)]
            )
        )
        #expect(solution.circle(1).map { close($0.radius, 4) } == true)
    }

    @Test func pointOnArc() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [.arc(center: SketchPoint(0, 0), radius: 5, from: 0, to: 1), .point(3, 3)],
                constraints: [.fixed(.center(0)), .radius(0, 5), .pointOnCircle(.point(1), curve: 0)]
            )
        )
        let point = try #require(solution.point(1))
        #expect(close((point.x * point.x + point.y * point.y).squareRoot(), 5))
    }

    @Test func tangentAtWithTheArcFirst() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [
                    .line(0, 0, 10, 0),
                    .arc(center: SketchPoint(10.5, 5.5), radius: 4, from: -1.4, to: 0),
                ],
                constraints: [.fixed(.start(0)), .fixed(.end(0)), .tangentAt(.start(1), .end(0)), .radius(1, 5)]
            )
        )
        #expect(solution.state == .underConstrained(dof: 1))
        #expect(solution.circle(1).map { close($0.center, SketchPoint(10, 5)) } == true)
    }
}
