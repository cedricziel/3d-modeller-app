@testable import _D_Modeller
import CADModel
import CADModelKernel
import CADModelSolvers
import Foundation
import Synchronization
import Testing

/// Holds every build until opened, and records the hinge value each build was asked for.
private final class BuildGate: Sendable {
    private let state = Mutex<(open: Bool, waiting: [CheckedContinuation<Void, Never>], values: [Double])>(
        (false, [], [])
    )

    var values: [Double] {
        state.withLock { $0.values }
    }

    func pass(_ value: Double) async {
        await withCheckedContinuation { continuation in
            let resume = state.withLock { state -> Bool in
                state.values.append(value)
                if state.open {
                    return true
                }
                state.waiting.append(continuation)
                return false
            }
            if resume {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiting = state.withLock { state in
            state.open = true
            defer { state.waiting = [] }
            return state.waiting
        }
        waiting.forEach { $0.resume() }
    }
}

@Suite("Joint driver")
@MainActor
struct JointDriverTests {
    private let hinged: CADDocument = {
        let plate = Part(
            name: "Plate",
            features: [Feature(name: "Box", kind: .primitive(PrimitiveFeature(.box(width: 10, depth: 10, height: 2))))]
        )
        let base = Instance(name: "Base", part: plate.id, grounded: true)
        let lid = Instance(name: "Lid", part: plate.id)
        let hinge = Joint(
            name: "Hinge", kind: .revolute, a: JointFrameRef(instance: base.id, face: .name("Box.top")),
            b: JointFrameRef(instance: lid.id, face: .name("Box.bottom")), limits: JointLimits(min: 0, max: 90)
        )
        return CADDocument(parts: [plate], assembly: Assembly(instances: [base, lid], joints: [hinge]))
    }()

    private func driver(_ gate: BuildGate) -> JointDriver {
        let engine = RebuildEngine(kernel: OCCTGeometryKernel(), assemblySolver: OndselAssemblySolver())
        return JointDriver { document in
            let value: Double =
                if case let .number(number)? = document.joints.first?.value {
                    number
                } else {
                    .nan
                }
            await gate.pass(value)
            return try await engine.rebuild(document)
        }
    }

    private func waitForBuilds(_ gate: BuildGate, count: Int) async {
        while gate.values.count < count {
            await Task.yield()
        }
    }

    @Test("Fast drives rebuild one at a time, skip the values overtaken while waiting, and show the newest")
    func latestWins() async {
        let gate = BuildGate()
        let driver = driver(gate)
        let hinge = hinged.joints[0].id

        driver.drive(hinge, to: 10, in: hinged)
        await waitForBuilds(gate, count: 1)
        driver.drive(hinge, to: 20, in: hinged)
        driver.drive(hinge, to: 30, in: hinged)
        gate.open()
        await driver.settle()

        #expect(gate.values == [10, 30])
        #expect(driver.previewed?.value == 30)
        #expect(driver.preview?.assembly?.joints.first?.value == 30)
        #expect(hinged.joints[0].value == nil)
    }

    @Test("Animate sweeps from the start to the end of the range and stops there")
    func animateSweeps() async {
        let gate = BuildGate()
        gate.open()
        let driver = driver(gate)

        await driver.animate(hinged.joints[0].id, in: hinged, over: 0...90, rate: 900)
        let values = gate.values

        #expect(values.first == 0)
        #expect(values.last == 90)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(!driver.isAnimating)
        #expect(driver.previewed?.value == 90)
    }

    @Test("Stop ends an animation where it is")
    func stopEndsAnimation() async {
        let gate = BuildGate()
        gate.open()
        let driver = driver(gate)
        let hinge = hinged.joints[0].id
        let document = hinged

        let running = Task { await driver.animate(hinge, in: document, over: 0...90, rate: 1) }
        await waitForBuilds(gate, count: 1)
        driver.stop()
        await running.value

        #expect(!driver.isAnimating)
        #expect((gate.values.last ?? 90) < 90)
    }

    @Test("Clearing drops the preview and any rebuild still running")
    func clearDropsPreview() async {
        let gate = BuildGate()
        let driver = driver(gate)

        driver.drive(hinged.joints[0].id, to: 45, in: hinged)
        await waitForBuilds(gate, count: 1)
        driver.clear()
        gate.open()
        await Task.yield()

        #expect(driver.preview == nil)
        #expect(driver.previewed == nil)
    }

    @Test("The slider runs through the limits, or a full turn for a hinge without them; animate likewise")
    func ranges() {
        let id = UUID()
        let limited = JointResult(id: id, name: "H", status: .ok, motion: .angle, minimum: 0, maximum: 110)
        let open = JointResult(id: id, name: "H", status: .ok, motion: .angle)
        let travel = JointResult(id: id, name: "S", status: .ok, motion: .travel, minimum: 5)

        #expect(JointMotionRange.slider(limited) == 0...110)
        #expect(JointMotionRange.slider(open) == -180...180)
        #expect(JointMotionRange.sweep(open) == 0...360)
        #expect(JointMotionRange.slider(travel) == nil)
        #expect(JointMotionRange.sweep(travel) == nil)
    }
}
