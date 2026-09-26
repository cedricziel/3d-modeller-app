import Testing

@testable import CADSolvers

struct ValidationTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let sketch: Sketch
        let expected: SketchSolverError
        var testDescription: String { name }
    }

    static let line = SketchEntity.line(0, 0, 10, 0)
    static let circle = SketchEntity.circle(center: SketchPoint(0, 0), radius: 5)
    static let arc = SketchEntity.arc(center: SketchPoint(0, 0), radius: 5, from: 0, to: .pi / 2)

    static let cases: [Case] = [
        Case(
            name: "NaN coordinate",
            sketch: Sketch(entities: [line, .point(.nan, 0)]),
            expected: .invalidEntity(index: 1, reason: "")
        ),
        Case(
            name: "infinite arc angle",
            sketch: Sketch(entities: [.arc(center: SketchPoint(0, 0), radius: 1, from: 0, to: .infinity)]),
            expected: .invalidEntity(index: 0, reason: "")
        ),
        Case(
            name: "zero radius",
            sketch: Sketch(entities: [.circle(center: SketchPoint(0, 0), radius: 0)]),
            expected: .invalidEntity(index: 0, reason: "")
        ),
        Case(
            name: "zero-length line",
            sketch: Sketch(entities: [line, .line(3, 3, 3, 3)]),
            expected: .invalidEntity(index: 1, reason: "")
        ),
        Case(
            name: "entity index out of range",
            sketch: Sketch(entities: [line, line], constraints: [.horizontal(0), .horizontal(5)]),
            expected: .invalidConstraint(index: 1, reason: "")
        ),
        Case(
            name: "negative entity index",
            sketch: Sketch(entities: [line], constraints: [.vertical(-1)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "horizontal circle",
            sketch: Sketch(entities: [circle], constraints: [.horizontal(0)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "centre of a line",
            sketch: Sketch(entities: [line], constraints: [.fixed(.center(0))]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "start of a circle",
            sketch: Sketch(entities: [circle], constraints: [.fixed(.start(0))]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "point role of a line",
            sketch: Sketch(entities: [line], constraints: [.fixed(.point(0))]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "parallel to itself",
            sketch: Sketch(entities: [line], constraints: [.parallel(0, 0)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "coincident with itself",
            sketch: Sketch(entities: [line], constraints: [.coincident(.start(0), .start(0))]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "negative distance",
            sketch: Sketch(entities: [line], constraints: [.distance(.start(0), .end(0), -1)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "zero radius constraint",
            sketch: Sketch(entities: [circle], constraints: [.radius(0, 0)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "diameter of a line",
            sketch: Sketch(entities: [line], constraints: [.diameter(0, 4)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "non-finite angle",
            sketch: Sketch(entities: [line, .line(0, 0, 0, 10)], constraints: [.angle(0, 1, .nan)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "tangent lines",
            sketch: Sketch(entities: [line, .line(0, 1, 10, 1)], constraints: [.tangent(0, 1)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "equal line and circle",
            sketch: Sketch(entities: [line, circle], constraints: [.equal(0, 1)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "tangentAt on a circle",
            sketch: Sketch(entities: [line, circle], constraints: [.tangentAt(.end(0), .start(1))]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "tangentAt at a centre",
            sketch: Sketch(entities: [line, arc], constraints: [.tangentAt(.end(0), .center(1))]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "tangentAt on one entity",
            sketch: Sketch(entities: [arc], constraints: [.tangentAt(.start(0), .end(0))]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "point on its own line",
            sketch: Sketch(entities: [line], constraints: [.pointOnLine(.start(0), line: 0)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "point on a line that is a circle",
            sketch: Sketch(entities: [.point(1, 1), circle], constraints: [.pointOnLine(.point(0), line: 1)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "point on a circle that is a line",
            sketch: Sketch(entities: [.point(1, 1), line], constraints: [.pointOnCircle(.point(0), curve: 1)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
        Case(
            name: "point-line distance to a circle",
            sketch: Sketch(entities: [.point(1, 1), circle], constraints: [.pointLineDistance(.point(0), line: 1, 2)]),
            expected: .invalidConstraint(index: 0, reason: "")
        ),
    ]

    @Test(arguments: cases)
    func invalidInputs(_ testCase: Case) {
        #expect {
            try SketchSolver().solve(testCase.sketch)
        } throws: { error in
            guard let error = error as? SketchSolverError else { return false }
            switch (error, testCase.expected) {
            case (.invalidEntity(let index, let reason), .invalidEntity(let expected, _)),
                (.invalidConstraint(let index, let reason), .invalidConstraint(let expected, _)):
                return index == expected && !reason.isEmpty
            default:
                return false
            }
        }
    }

    @Test func validSketchPassesValidation() throws {
        let sketch = Sketch(
            entities: [Self.line, Self.arc, .point(3, 4, construction: true)],
            constraints: [.tangentAt(.end(0), .start(1)), .pointOnCircle(.point(2), curve: 1), .radius(1, 5)]
        )
        try sketch.validate()
    }
}
