import Testing

@testable import CADSolvers

struct SolveTests {
    let solver = SketchSolver()

    private func expectRectangleCorners(_ solution: SketchSolution) {
        let corners = [SketchPoint(0, 0), SketchPoint(60, 0), SketchPoint(60, 40), SketchPoint(0, 40)]
        for index in 0..<4 {
            let line = solution.line(index)
            #expect(line.map { close($0.start, corners[index]) } == true, "start of line \(index)")
            #expect(line.map { close($0.end, corners[(index + 1) % 4]) } == true, "end of line \(index)")
        }
    }

    @Test func rectangle() throws {
        let solution = try solver.solve(Fixtures.exactRectangle)
        #expect(solution.state == .fullyConstrained)
        #expect(solution.degreesOfFreedom == 0)
        expectRectangleCorners(solution)
    }

    @Test func sloppyRectangle() throws {
        let solution = try solver.solve(Fixtures.rectangle(Fixtures.sloppyEnds))
        #expect(solution.state == .fullyConstrained)
        expectRectangleCorners(solution)
    }

    @Test func underConstrained() throws {
        let point = try solver.solve(Sketch(entities: [.point(1, 2)]))
        #expect(point.state == .underConstrained(dof: 2))
        #expect(point.point(0) == SketchPoint(1, 2))

        let line = try solver.solve(Sketch(entities: [.line(0, 0, 3, 4)]))
        #expect(line.state == .underConstrained(dof: 4))

        let undimensioned = try solver.solve(Fixtures.rectangle(Fixtures.sloppyEnds, dimensions: false))
        #expect(undimensioned.state == .underConstrained(dof: 2))
        #expect(undimensioned.degreesOfFreedom == 2)

        let floating = try solver.solve(Fixtures.rectangle(Fixtures.sloppyEnds, fixed: false))
        #expect(floating.state == .underConstrained(dof: 2))
    }

    private func tangentLineArc(centerY: Double) throws -> SketchSolution {
        try solver.solve(
            Sketch(
                entities: [
                    .line(-20, 0, 20, 0),
                    .arc(center: SketchPoint(5, centerY), radius: 10, from: 0.2, to: 2.5),
                    .line(5, -30, 5, 30, construction: true),
                ],
                constraints: [
                    .fixed(.start(0)), .fixed(.end(0)), .fixed(.start(2)), .fixed(.end(2)),
                    .pointOnLine(.center(1), line: 2),
                    .radius(1, 10),
                    .tangent(0, 1),
                ]
            )
        )
    }

    @Test func tangentLineArc() throws {
        let solution = try tangentLineArc(centerY: 8)
        #expect(solution.state == .underConstrained(dof: 2))
        #expect(solution.circle(1).map { close($0.center, SketchPoint(5, 10)) } == true)
    }

    @Test func tangentKeepsSide() throws {
        let solution = try tangentLineArc(centerY: -8)
        #expect(solution.circle(1).map { close($0.center, SketchPoint(5, -10)) } == true)
    }

    @Test(arguments: [(18.0, 15.0), (3.0, 5.0)])
    func tangentCircles(startX: Double, expectedX: Double) throws {
        let solution = try solver.solve(
            Sketch(
                entities: [
                    .circle(center: SketchPoint(0, 0), radius: 10),
                    .circle(center: SketchPoint(startX, 0), radius: 5),
                    .line(-50, 0, 50, 0, construction: true),
                ],
                constraints: [
                    .fixed(.center(0)), .radius(0, 10), .radius(1, 5),
                    .fixed(.start(2)), .fixed(.end(2)), .pointOnLine(.center(1), line: 2),
                    .tangent(0, 1),
                ]
            )
        )
        #expect(solution.state == .fullyConstrained)
        #expect(solution.circle(1).map { close($0.center, SketchPoint(expectedX, 0)) } == true)
    }

    @Test func tangentAtJoint() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [
                    .line(0, 0, 10, 0),
                    .arc(center: SketchPoint(10.5, 5.5), radius: 4, from: -1.4, to: 0),
                ],
                constraints: [
                    .fixed(.start(0)), .fixed(.end(0)),
                    .tangentAt(.end(0), .start(1)),
                    .radius(1, 5),
                ]
            )
        )
        #expect(solution.state == .underConstrained(dof: 1))
        #expect(solution.circle(1).map { close($0.center, SketchPoint(10, 5)) } == true)
        #expect(solution.arcAngles(1).map { close(normalized($0.start), -.pi / 2) } == true)
    }

    @Test func radiusAndDiameter() throws {
        let radius = try solver.solve(
            Sketch(
                entities: [.circle(center: SketchPoint(0, 0), radius: 3)],
                constraints: [.fixed(.center(0)), .radius(0, 7)]
            )
        )
        #expect(radius.state == .fullyConstrained)
        #expect(radius.circle(0).map { close($0.radius, 7) } == true)

        let diameter = try solver.solve(
            Sketch(
                entities: [.arc(center: SketchPoint(0, 0), radius: 3, from: 0, to: 1)],
                constraints: [.fixed(.center(0)), .diameter(0, 10)]
            )
        )
        #expect(diameter.state == .underConstrained(dof: 2))
        #expect(diameter.circle(0).map { close($0.radius, 5) } == true)
    }

    /// A fixed horizontal reference line of length 10 and a second line from the origin whose
    /// length is 10 and whose direction the constraint under test settles.
    private func secondLine(from start: SketchPoint, to end: SketchPoint, _ constraint: SketchConstraint) throws
        -> SketchSolution
    {
        try solver.solve(
            Sketch(
                entities: [.line(0, 0, 10, 0), SketchEntity(.line(start: start, end: end))],
                constraints: [
                    .fixed(.start(0)), .fixed(.end(0)), .fixed(.start(1)),
                    .distance(.start(1), .end(1), 10),
                    constraint,
                ]
            )
        )
    }

    @Test func angleBetweenLines() throws {
        let solution = try secondLine(from: SketchPoint(0, 0), to: SketchPoint(5, 9), .angle(0, 1, .pi / 3))
        #expect(solution.state == .fullyConstrained)
        #expect(solution.line(1).map { close($0.end, SketchPoint(5, 10 * 3.0.squareRoot() / 2)) } == true)
    }

    @Test func perpendicularLines() throws {
        let solution = try secondLine(from: SketchPoint(0, 0), to: SketchPoint(1, 9), .perpendicular(0, 1))
        #expect(solution.state == .fullyConstrained)
        #expect(solution.line(1).map { close($0.end, SketchPoint(0, 10)) } == true)
    }

    @Test func parallelLines() throws {
        let solution = try secondLine(from: SketchPoint(0, 5), to: SketchPoint(9, 7), .parallel(0, 1))
        #expect(solution.state == .fullyConstrained)
        #expect(solution.line(1).map { close($0.end, SketchPoint(10, 5)) } == true)
    }

    @Test func equalLines() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [.line(0, 0, 10, 0), .line(0, 5, 4, 6)],
                constraints: [.fixed(.start(0)), .fixed(.end(0)), .fixed(.start(1)), .horizontal(1), .equal(0, 1)]
            )
        )
        #expect(solution.state == .fullyConstrained)
        #expect(solution.line(1).map { close($0.end, SketchPoint(10, 5)) } == true)
    }

    @Test(arguments: [(4.0, 2.0), (-4.0, -2.0)])
    func pointLineDistance(startY: Double, expectedY: Double) throws {
        let solution = try solver.solve(
            Sketch(
                entities: [.line(0, 0, 10, 0), .point(3, startY)],
                constraints: [.fixed(.start(0)), .fixed(.end(0)), .pointLineDistance(.point(1), line: 0, 2)]
            )
        )
        #expect(solution.state == .underConstrained(dof: 1))
        #expect(solution.point(1).map { close($0.y, expectedY) } == true)
    }

    @Test func pointOnCircle() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [.circle(center: SketchPoint(0, 0), radius: 5), .point(3, 3)],
                constraints: [.fixed(.center(0)), .radius(0, 5), .pointOnCircle(.point(1), curve: 0)]
            )
        )
        #expect(solution.state == .underConstrained(dof: 1))
        let point = try #require(solution.point(1))
        #expect(close((point.x * point.x + point.y * point.y).squareRoot(), 5))
    }

    @Test func coincidentPoints() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [.point(1, 1), .point(4, 5)],
                constraints: [.fixed(.point(0)), .coincident(.point(0), .point(1))]
            )
        )
        #expect(solution.state == .fullyConstrained)
        #expect(solution.point(1).map { close($0, SketchPoint(1, 1)) } == true)
    }

    @Test func constructionFlagPreserved() throws {
        let sketch = Sketch(entities: [.line(0, 0, 1, 1, construction: true), .point(2, 2)])
        let solution = try solver.solve(sketch)
        #expect(solution.entities.map(\.construction) == [true, false])
    }

    @Test func solvedArcAnglesAreNormalised() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [.arc(center: SketchPoint(0, 0), radius: 5, from: 2.21 + 4 * .pi, to: 0.32)],
                constraints: [.fixed(.center(0)), .radius(0, 5)]
            )
        )
        let angles = try #require(solution.arcAngles(0))
        #expect(close(angles.start, 2.21))
        #expect(close(angles.end, 0.32 + 2 * .pi))
    }
}
