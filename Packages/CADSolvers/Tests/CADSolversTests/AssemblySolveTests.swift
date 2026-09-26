import CADSolvers
import Testing
import simd

struct AssemblySolveTests {
    typealias F = AssemblyFixtures
    let solver = AssemblySolver()

    @Test func revoluteAlignsOriginsAndAxes() throws {
        let system = F.twoBodies(.revolute, start: F.placement(5, 3, 2))
        let solution = try solver.solve(system)
        let frame = F.frameB(system, solution)
        #expect(solution.joints == [.satisfied])
        #expect(F.close(frame.translation, SIMD3(0, 0, 10)))
        #expect(F.close(frame.rotation.columns.2, SIMD3(0, 0, 1)))
        #expect(solution.placements[0] == .identity)
    }

    @Test func fixedCoincides() throws {
        let system = F.twoBodies(.fixed, start: F.placement(40, -20, 70, degrees: 30))
        let solution = try solver.solve(system)
        let frame = F.frameB(system, solution)
        #expect(solution.joints == [.satisfied])
        #expect(F.close(frame.translation, F.baseMarker.translation))
        #expect(F.close(frame.rotation, F.baseMarker.rotation))
    }

    @Test func sliderKeepsPositionAlongAxis() throws {
        let system = F.twoBodies(.slider, start: F.placement(2, 1, 25))
        let solution = try solver.solve(system)
        let placement = solution.placements[1]
        #expect(solution.joints == [.satisfied])
        #expect(F.close(placement.translation, SIMD3(0, 0, 25)))
        #expect(F.close(placement.rotation, matrix_identity_double3x3))
    }

    @Test func cylindricalAllowsTurn() throws {
        let start = F.placement(2, 1, 25, degrees: 20)
        let solution = try solver.solve(F.twoBodies(.cylindrical, start: start))
        let placement = solution.placements[1]
        #expect(solution.joints == [.satisfied])
        #expect(F.close(placement.translation, SIMD3(0, 0, 25)))
        #expect(F.close(placement.rotation, start.rotation))
    }

    @Test func ballJoinsPoints() throws {
        let marker = F.placement(0, 0, -4)
        let start = F.placement(3, 3, 3, axis: SIMD3(1, 1, 0), degrees: 25)
        let system = F.twoBodies(.ball, start: start, markerB: marker)
        let solution = try solver.solve(system)
        #expect(solution.joints == [.satisfied])
        #expect(F.close(F.frameB(system, solution).translation, SIMD3(0, 0, 10)))
    }

    @Test func planarKeepsInPlaneOffset() throws {
        let start = F.placement(5, 3, 2, degrees: 36.87)
        let solution = try solver.solve(F.twoBodies(.planar, start: start))
        let placement = solution.placements[1]
        #expect(solution.joints == [.satisfied])
        #expect(F.close(placement.translation, SIMD3(5, 3, 10)))
        #expect(F.close(placement.rotation, start.rotation))
    }

    @Test func chain() throws {
        let system = AssemblySystem(
            bodies: [
                AssemblyBody(placement: .identity, grounded: true), AssemblyBody(placement: F.placement(1, 0, 0)),
                AssemblyBody(placement: F.placement(0, 7, 3)),
            ],
            joints: [
                AssemblyJoint(.revolute, 0, F.baseMarker, 1, .identity),
                AssemblyJoint(.fixed, 1, F.placement(20, 0, 0), 2, F.placement(0, 0, -5)),
            ]
        )
        let solution = try solver.solve(system)
        #expect(solution.joints == [.satisfied, .satisfied])
        let tip = F.frameB(system, solution, joint: 1).translation
        #expect(abs(tip.z - 10) < 1e-6)
        #expect(abs(simd_length(SIMD2(tip.x, tip.y)) - 20) < 1e-6)
    }
}
