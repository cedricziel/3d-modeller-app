@testable import CADSolvers
import Testing

struct AttemptChoiceTests {
    private func attempt(distance: Double, failure: String?) -> AssemblySolver.Attempt {
        AssemblySolver.Attempt(
            placements: [.identity], joints: [.unsatisfied(distance: distance, angle: 0)], failure: failure,
            failures: 1
        )
    }

    @Test("A retry that ties a thrown first attempt without throwing is kept, since it really solved")
    func tieKeepsTheSolvedAttempt() {
        let solution = AssemblySolver.better(attempt(distance: 1, failure: "boom"), attempt(distance: 2, failure: nil))

        #expect(solution.joints == [.unsatisfied(distance: 2, angle: 0)])
        #expect(solution.failure == nil)
        #expect(solution.attempts == 2)
    }

    @Test("On a tie where neither or both threw, the first attempt is kept, with its message when both threw")
    func tieKeepsFirst() {
        let neither = AssemblySolver.better(attempt(distance: 1, failure: nil), attempt(distance: 2, failure: nil))
        let both = AssemblySolver.better(attempt(distance: 1, failure: "boom"), attempt(distance: 2, failure: "bang"))

        #expect(neither.joints == [.unsatisfied(distance: 1, angle: 0)])
        #expect(both.joints == [.unsatisfied(distance: 1, angle: 0)])
        #expect(both.failure == "boom")
    }

    @Test("A retry with fewer failures that threw keeps its message")
    func winnerThatThrewReports() {
        let first = attempt(distance: 1, failure: nil)
        let second = AssemblySolver.Attempt(
            placements: [.identity], joints: [.satisfied], failure: "bang", failures: 0)

        #expect(AssemblySolver.better(first, second).failure == "bang")
    }
}
