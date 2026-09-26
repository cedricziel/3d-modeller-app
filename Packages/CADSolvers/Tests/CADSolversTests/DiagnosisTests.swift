import Testing

@testable import CADSolvers

struct DiagnosisTests {
    let solver = SketchSolver()

    @Test func conflictingDistances() throws {
        let sketch = Sketch(
            entities: [.point(0, 0), .point(12, 1)],
            constraints: [
                .fixed(.point(0)),
                .distance(.point(0), .point(1), 10),
                .distance(.point(0), .point(1), 20),
            ]
        )
        let solution = try solver.solve(sketch)
        #expect(solution.state == .overConstrained(conflicting: [1, 2]))
        #expect(solution.entities == sketch.entities)
    }

    @Test func conflictingWidth() throws {
        var sketch = Fixtures.exactRectangle
        sketch.constraints.append(.distance(.start(2), .end(2), 70))
        let solution = try solver.solve(sketch)
        // PlaneGCS names every constraint of the contradicting group: both widths and the
        // coincidences and verticals that tie the top line's length to the bottom one's.
        #expect(solution.state == .overConstrained(conflicting: [0, 1, 2, 3, 6, 7, 9, 11]))
    }

    @Test func horizontalBetweenFixedEnds() throws {
        let sketch = Sketch(
            entities: [.line(0, 0, 10, 5)],
            constraints: [.fixed(.start(0)), .horizontal(0), .fixed(.end(0))]
        )
        let solution = try solver.solve(sketch)
        #expect(solution.state == .overConstrained(conflicting: [0, 1, 2]))
    }

    @Test func redundantParallel() throws {
        var sketch = Fixtures.rectangle(Fixtures.sloppyEnds)
        sketch.constraints.append(.parallel(0, 2))
        let solution = try solver.solve(sketch)
        #expect(solution.state == .redundant([11]))
        #expect(solution.line(0).map { close($0.end, SketchPoint(60, 0)) } == true)
    }

    @Test func coincidentWithEdgeTangentIsImprecise() throws {
        let solution = try solver.solve(
            Sketch(
                entities: [
                    .line(0, 0, 10, 0),
                    .arc(center: SketchPoint(10.5, 5.5), radius: 4, from: -1.4, to: 0),
                ],
                constraints: [
                    .fixed(.start(0)), .fixed(.end(0)),
                    .coincident(.end(0), .start(1)),
                    .tangent(0, 1),
                    .radius(1, 5),
                ]
            )
        )
        #expect(solution.state == .underConstrained(dof: 1))
        // The joint is a double root of "on the line" and "tangent to the line", so the solver
        // only gets within about 1e-5; `tangentAt` has no such root (see SolveTests).
        #expect(solution.circle(1).map { close($0.center, SketchPoint(10, 5), tolerance: 1e-4) } == true)
    }

    @Test func emptySketch() throws {
        let solution = try solver.solve(Sketch())
        #expect(solution.state == .fullyConstrained)
        #expect(solution.degreesOfFreedom == 0)
        #expect(solution.entities.isEmpty)
    }
}
