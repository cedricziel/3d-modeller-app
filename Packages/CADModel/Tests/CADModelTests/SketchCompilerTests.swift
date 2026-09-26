@testable import CADModel
import Foundation
import Testing

@Suite("Sketch compilation")
struct SketchCompilerTests {
    let parameters = ParameterTable([Parameter(name: "width", expression: 60)])

    @Test("A dimensioned rectangle compiles into indices, values and a moved fixed point")
    func compilesRectangle() throws {
        var sketch = rectangleSketch
        sketch.entities[0].geometry = .line(start: SketchPoint2(3, 4), end: SketchPoint2(60, 0))
        let system = try SketchCompiler.compile(sketch, parameters: parameters)

        #expect(system.entities[0] == SolverEntity(geometry: .line(SIMD2(0, 0), SIMD2(60, 0)), construction: false))
        let expected: [SolverConstraint] = [
            .coincident(.end(0), .start(1)), .coincident(.end(1), .start(2)), .coincident(.end(2), .start(3)),
            .coincident(.end(3), .start(0)), .horizontal(0), .horizontal(2), .vertical(1), .vertical(3),
            .fixed(.start(0)), .distance(.start(0), .end(0), 60), .distance(.start(1), .end(1), 40),
        ]
        #expect(system.constraints == expected)
    }

    @Test("Arc angles and angle values become radians")
    func anglesInRadians() throws {
        let sketch = SketchFeature(
            plane: .base(.xy),
            entities: [
                SketchEntity(name: "arc1", .arc(center: SketchPoint2(0, 0), radius: 5, startAngle: 0, endAngle: 90)),
                SketchEntity(name: "line1", .line(start: SketchPoint2(0, 0), end: SketchPoint2(1, 0))),
                SketchEntity(name: "line2", .line(start: SketchPoint2(0, 0), end: SketchPoint2(0, 1))),
                SketchEntity(name: "point1", .point(SketchPoint2(2, 2))),
            ],
            constraints: [
                SketchConstraint(name: "c1", .angle, entities: ["line1", "line2"], value: 30),
                SketchConstraint(name: "c2", .pointOnCircle, entities: ["arc1"], points: ["point1"]),
                SketchConstraint(name: "c3", .coincident, points: ["arc1.center", "line1.start"]),
            ]
        )
        let system = try SketchCompiler.compile(sketch, parameters: parameters)

        let arc = SolverGeometry.arc(center: SIMD2(0, 0), radius: 5, startAngle: 0, endAngle: .pi / 2)
        #expect(system.entities[0].geometry == arc)
        #expect(system.constraints[0] == .angle(1, 2, .pi / 6))
        #expect(system.constraints[1] == .pointOnCircle(.point(3), curve: 0))
        #expect(system.constraints[2] == .coincident(.center(0), .start(1)))
    }

    @Test("A solution comes back in degrees with names and construction flags")
    func solutionBackToDegrees() {
        let sketch = SketchFeature(
            plane: .base(.xy),
            entities: [
                SketchEntity(
                    name: "arc7", .arc(center: SketchPoint2(0, 0), radius: 1, startAngle: 0, endAngle: 45),
                    construction: true
                )
            ]
        )
        let solution = SolverSolution(
            entities: [
                SolverEntity(
                    geometry: .arc(center: SIMD2(1, 2), radius: 3, startAngle: .pi / 2, endAngle: .pi),
                    construction: true
                )
            ], state: .fullyConstrained, degreesOfFreedom: 0
        )
        let entities = SketchCompiler.entities(solution, of: sketch)

        let expected = SketchEntity(
            name: "arc7", .arc(center: SketchPoint2(1, 2), radius: 3, startAngle: 90, endAngle: 180), construction: true
        )
        #expect(entities == [expected])
    }

    static let errorCases: [(SketchConstraint, String)] = [
        (SketchConstraint(name: "c20", .horizontal, entities: ["line9"]), "no entity named 'line9'"),
        (SketchConstraint(name: "c20", .coincident, points: ["line1.center", "line2.start"]), "line1.center"),
        (SketchConstraint(name: "c20", .coincident, points: ["line1", "line2.start"]), "line1.start or line1.end"),
        (SketchConstraint(name: "c20", .distance, points: ["line1.start"], value: 3), "needs 2 points"),
        (SketchConstraint(name: "c20", .horizontal, entities: ["line1", "line2"]), "needs 1 entity"),
        (SketchConstraint(name: "c20", .radius, entities: ["line1"]), "needs a value"),
        (SketchConstraint(name: "c20", .vertical, entities: ["line1"], value: 3), "takes no value"),
        (
            SketchConstraint(name: "c20", .distance, points: ["line1.start", "line1.end"], value: 3, at: [0, 0]), "'at'"
        ),
        (SketchConstraint(name: "c20", .fixed, points: ["line1.start"], at: [0]), "'at'"),
        (SketchConstraint(name: "c20", .distance, points: ["line1.start", "line1.end"], value: "nope"), "value"),
        (SketchConstraint(name: "c1", .horizontal, entities: ["line1"]), "more than one constraint named 'c1'"),
    ]

    @Test("Bad constraints fail with the constraint's name and the problem", arguments: errorCases)
    func compileErrors(constraint: SketchConstraint, expected: String) {
        var sketch = rectangleSketch
        sketch.constraints.append(constraint)
        #expect {
            try SketchCompiler.compile(sketch, parameters: parameters)
        } throws: { error in
            let text = String(describing: error)
            return text.contains(constraint.name) && text.contains(expected)
        }
    }

    @Test("Duplicate entity names fail")
    func duplicateEntity() {
        var sketch = rectangleSketch
        sketch.entities.append(SketchEntity(name: "line1", .point(SketchPoint2(0, 0))))
        #expect {
            try SketchCompiler.compile(sketch, parameters: parameters)
        } throws: { error in
            String(describing: error).contains("more than one entity named 'line1'")
        }
    }

    @Test("Solver states name constraints and read as text")
    func stateNames() {
        let over = SketchCompiler.state(.overConstrained(conflicting: [0, 2]), of: rectangleSketch)
        #expect(over == .overConstrained(conflicting: ["c1", "c3"]))
        #expect(over.description == "over-constrained, c1, c3 conflict")
        #expect(SketchCompiler.state(.redundant([6]), of: rectangleSketch).description == "redundant: c7")
        #expect(SketchSolveState.underConstrained(dof: 2).description == "under-constrained, 2 degrees of freedom")
        #expect(SketchSolveState.underConstrained(dof: 1).description == "under-constrained, 1 degree of freedom")
        #expect(SketchSolveState.fullyConstrained.description == "fully constrained")
        #expect(SketchSolveState.failed.description == "solve failed")
    }
}
