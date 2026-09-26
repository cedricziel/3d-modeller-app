import CADSolvers
import Foundation
import Testing
import simd

struct AssemblyDiagnosisTests {
    typealias F = AssemblyFixtures
    let solver = AssemblySolver()

    @Test func conflictingFixedJoints() throws {
        let system = AssemblySystem(
            bodies: [
                AssemblyBody(placement: .identity, grounded: true), AssemblyBody(placement: F.placement(1, 1, 1)),
            ],
            joints: [
                AssemblyJoint(.fixed, 0, F.baseMarker, 1, .identity),
                AssemblyJoint(.fixed, 0, F.placement(0, 0, 20), 1, .identity),
            ]
        )
        let solution = try solver.solve(system)
        #expect(solution.joints == [.conflicting, .redundant])
        let translation = solution.placements[1].translation
        #expect(translation.x.isFinite && translation.y.isFinite && translation.z.isFinite)
    }

    @Test func flippedStartRetries() throws {
        let system = F.twoBodies(.fixed, start: F.placement(0, 0, 30, axis: SIMD3(1, 0, 0), degrees: 180))
        let solution = try solver.solve(system)
        let frame = F.frameB(system, solution)
        #expect(solution.joints == [.satisfied])
        #expect(solution.attempts == 2)
        #expect(F.close(frame.rotation, matrix_identity_double3x3))
        #expect(F.close(frame.translation, SIMD3(0, 0, 10)))
    }

    @Test func singularStartRetries() throws {
        let system = F.twoBodies(.fixed, start: F.placement(50, -30, 80, axis: SIMD3(0, 1, 0), degrees: 90))
        let solution = try solver.solve(system)
        #expect(solution.joints == [.satisfied])
        #expect(solution.attempts == 2)
    }

    @Test func redundantPairReported() throws {
        let system = AssemblySystem(
            bodies: [
                AssemblyBody(placement: .identity, grounded: true), AssemblyBody(placement: F.placement(0, 0, 10)),
            ],
            joints: [
                AssemblyJoint(.revolute, 0, F.baseMarker, 1, .identity),
                AssemblyJoint(.cylindrical, 0, F.baseMarker, 1, .identity),
            ]
        )
        let solution = try solver.solve(system)
        #expect(solution.joints == [.satisfied, .redundant])
    }

    @Test func islandKeepsPlacement() throws {
        let island = F.placement(100, 0, 0)
        let system = AssemblySystem(
            bodies: [
                AssemblyBody(placement: .identity, grounded: true), AssemblyBody(placement: island),
                AssemblyBody(placement: F.placement(0, 100, 0)),
            ],
            joints: [AssemblyJoint(.fixed, 1, .identity, 2, .identity)]
        )
        let solution = try solver.solve(system)
        #expect(solution.placements[1] == island)
        #expect(solution.joints == [.notConnected])
    }

    @Test func groundedPairJudged() throws {
        let bodies = [
            AssemblyBody(placement: .identity, grounded: true),
            AssemblyBody(placement: F.placement(0, 0, 10), grounded: true),
        ]
        let coincident = try solver.solve(
            AssemblySystem(bodies: bodies, joints: [AssemblyJoint(.fixed, 0, F.baseMarker, 1, .identity)]))
        #expect(coincident.joints == [.satisfied])
        let apart = try solver.solve(
            AssemblySystem(bodies: bodies, joints: [AssemblyJoint(.fixed, 0, F.placement(3, 0, 10), 1, .identity)]))
        guard case .unsatisfied(let distance, _) = apart.joints.first else {
            Issue.record("expected unsatisfied, got \(apart.joints)")
            return
        }
        #expect(abs(distance - 3) < 1e-9)
    }

    @Test func concurrentSolves() async throws {
        let system = F.twoBodies(.revolute, start: F.placement(5, 3, 2))
        let solver = self.solver
        let solutions = try await withThrowingTaskGroup(of: AssemblySolution.self) { group in
            for _ in 0..<8 { group.addTask { try solver.solve(system) } }
            var all: [AssemblySolution] = []
            for try await solution in group { all.append(solution) }
            return all
        }
        #expect(solutions.count == 8)
        #expect(Set(solutions).count == 1)
    }

    @Test func timing() throws {
        var bodies = [AssemblyBody(placement: .identity, grounded: true)]
        var joints: [AssemblyJoint] = []
        for index in 1...20 {
            bodies.append(AssemblyBody(placement: F.placement(Double(index) * 11, 1, 0.5)))
            joints.append(AssemblyJoint(.revolute, index - 1, F.placement(10, 0, 0), index, .identity))
        }
        let start = Date()
        let solution = try solver.solve(AssemblySystem(bodies: bodies, joints: joints))
        let elapsed = Date().timeIntervalSince(start)
        #expect(solution.joints.allSatisfy { $0 == .satisfied })
        #expect(elapsed < 5, "20 revolute links took \(elapsed) s")
    }
}
