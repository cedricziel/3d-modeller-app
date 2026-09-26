import CADSolvers
import Testing
import simd

struct AssemblyValidationTests {
    let solver = AssemblySolver()

    static let cases: [(String, AssemblySystem, AssemblySolverError)] = {
        let ground = AssemblyBody(placement: .identity, grounded: true)
        let free = AssemblyBody(placement: .identity)
        let skewed = simd_double3x3(rows: [SIMD3(1, 0.1, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)])
        let mirrored = simd_double3x3(diagonal: SIMD3(1, 1, -1))
        let revolute = AssemblyJoint(.revolute, 0, .identity, 1, .identity)
        return [
            (
                "NaN translation",
                AssemblySystem(bodies: [
                    ground, AssemblyBody(placement: RigidPlacement(translation: SIMD3(.nan, 0, 0))),
                ]),
                .invalidBody(index: 1, reason: "")
            ),
            (
                "skewed rotation",
                AssemblySystem(bodies: [AssemblyBody(placement: RigidPlacement(rotation: skewed), grounded: true)]),
                .invalidBody(index: 0, reason: "")
            ),
            (
                "reflection",
                AssemblySystem(bodies: [ground, AssemblyBody(placement: RigidPlacement(rotation: mirrored))]),
                .invalidBody(index: 1, reason: "")
            ),
            (
                "body out of range",
                AssemblySystem(bodies: [ground, free], joints: [AssemblyJoint(.fixed, 0, .identity, 5, .identity)]),
                .invalidJoint(index: 0, reason: "")
            ),
            (
                "same body twice",
                AssemblySystem(bodies: [ground, free], joints: [AssemblyJoint(.fixed, 1, .identity, 1, .identity)]),
                .invalidJoint(index: 0, reason: "")
            ),
            (
                "NaN marker",
                AssemblySystem(
                    bodies: [ground, free],
                    joints: [
                        revolute,
                        AssemblyJoint(.ball, 0, RigidPlacement(translation: SIMD3(0, .infinity, 0)), 1, .identity),
                    ]),
                .invalidJoint(index: 1, reason: "")
            ),
            ("nothing grounded", AssemblySystem(bodies: [free, free], joints: [revolute]), .nothingGrounded),
        ]
    }()

    @Test(arguments: cases.indices)
    func invalidInputs(_ index: Int) {
        let (name, system, expected) = Self.cases[index]
        do {
            _ = try solver.solve(system)
            Issue.record("\(name) solved")
        } catch {
            switch (error, expected) {
            case (.invalidBody(let got, let reason), .invalidBody(let want, _)):
                #expect(got == want, "\(name)")
                #expect(!reason.isEmpty)
            case (.invalidJoint(let got, let reason), .invalidJoint(let want, _)):
                #expect(got == want, "\(name)")
                #expect(!reason.isEmpty)
            case (.nothingGrounded, .nothingGrounded):
                break
            default:
                Issue.record("\(name): \(error)")
            }
        }
    }

    @Test func noJointsReturnsPlacements() throws {
        let start = AssemblyFixtures.placement(1, 2, 3, degrees: 40)
        let solution = try solver.solve(AssemblySystem(bodies: [AssemblyBody(placement: start)]))
        #expect(solution.placements == [start])
        #expect(solution.joints.isEmpty)
        #expect(solution.failure == nil)
    }
}
