import CADModel
import CADModelSolvers
import Testing
import simd

@Suite("PlaneGCS sketch solver")
struct PlaneGCSSketchSolverTests {
    let solver = PlaneGCSSketchSolver()

    @Test("A sloppy rectangle solves fully constrained onto its dimensions")
    func rectangle() throws {
        let entities: [SolverEntity] = [
            SolverEntity(geometry: .line(SIMD2(0, 0), SIMD2(58, 2)), construction: false),
            SolverEntity(geometry: .line(SIMD2(58, 2), SIMD2(61, 39)), construction: false),
            SolverEntity(geometry: .line(SIMD2(61, 39), SIMD2(-1, 41)), construction: false),
            SolverEntity(geometry: .line(SIMD2(-1, 41), SIMD2(0, 0)), construction: true),
        ]
        let constraints: [SolverConstraint] = [
            .coincident(.end(0), .start(1)), .coincident(.end(1), .start(2)), .coincident(.end(2), .start(3)),
            .coincident(.end(3), .start(0)), .horizontal(0), .horizontal(2), .vertical(1), .vertical(3),
            .fixed(.start(0)), .distance(.start(0), .end(0), 60), .distance(.start(1), .end(1), 40),
        ]
        let solution = try solver.solve(SolverSketch(entities: entities, constraints: constraints))

        #expect(solution.state == .fullyConstrained)
        #expect(solution.degreesOfFreedom == 0)
        guard case .line(let start, let end) = solution.entities[1].geometry else {
            Issue.record("not a line")
            return
        }
        #expect(simd_distance(start, SIMD2(60, 0)) < 1e-9)
        #expect(simd_distance(end, SIMD2(60, 40)) < 1e-9)
        #expect(solution.entities[3].construction)
    }

    @Test("Every constraint kind maps onto the solver")
    func everyKind() throws {
        let entities: [SolverEntity] = [
            SolverEntity(geometry: .line(SIMD2(0, 0), SIMD2(10, 0)), construction: false),
            SolverEntity(geometry: .line(SIMD2(0, 5), SIMD2(10, 6)), construction: false),
            SolverEntity(geometry: .circle(center: SIMD2(20, 20), radius: 3), construction: false),
            SolverEntity(
                geometry: .arc(center: SIMD2(0, 20), radius: 4, startAngle: 0, endAngle: .pi / 2), construction: false),
            SolverEntity(geometry: .point(SIMD2(5, 9)), construction: false),
            SolverEntity(geometry: .line(SIMD2(40, 0), SIMD2(40, 10)), construction: false),
        ]
        let constraints: [SolverConstraint] = [
            .parallel(0, 1), .pointLineDistance(.start(1), line: 0, 5), .equal(2, 3), .radius(2, 3), .diameter(3, 6),
            .pointOnLine(.point(4), line: 1), .pointOnCircle(.center(2), curve: 3), .perpendicular(0, 5),
            .angle(0, 1, 0), .tangent(5, 2), .tangentAt(.end(0), .start(5)), .distance(.point(4), .start(1), 4),
            .vertical(5), .horizontal(0), .coincident(.center(3), .start(0)),
        ]
        let solution = try solver.solve(SolverSketch(entities: entities, constraints: constraints))
        #expect(solution.entities.count == entities.count)
    }

    @Test("A refused constraint names its index")
    func refusal() {
        let sketch = SolverSketch(
            entities: [SolverEntity(geometry: .circle(center: .zero, radius: 1), construction: false)],
            constraints: [.radius(0, 2), .horizontal(0)])
        #expect {
            try solver.solve(sketch)
        } throws: { error in
            (error as? SketchSolvingError)?.constraint == 1
        }
    }

    @Test("Conflicts come back as constraint indices")
    func conflicts() throws {
        let sketch = SolverSketch(
            entities: [
                SolverEntity(geometry: .point(.zero), construction: false),
                SolverEntity(geometry: .point(SIMD2(5, 0)), construction: false),
            ],
            constraints: [.fixed(.point(0)), .distance(.point(0), .point(1), 10), .distance(.point(0), .point(1), 20)])
        #expect(try solver.solve(sketch).state == .overConstrained(conflicting: [1, 2]))
    }
}
