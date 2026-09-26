import CADModel
import Foundation
import Observation

/// Shows a joint at values the document does not hold yet: while a slider moves or an animation runs, it rebuilds
/// the document with the new value off the main actor and publishes that result, never editing the document.
@MainActor
@Observable
final class JointDriver {
    typealias Build = @Sendable (CADDocument) async throws -> RebuildResult

    /// The latest previewed rebuild; nil shows the document as it is.
    private(set) var preview: RebuildResult?
    /// The joint and value `preview` shows.
    private(set) var previewed: (joint: UUID, value: Double)?
    private(set) var isAnimating = false

    @ObservationIgnored private let build: Build
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var pending: (document: CADDocument, joint: UUID, value: Double)?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var animation: Task<Void, Never>?
    /// Bumped by `clear`, so rebuilds that finish afterwards are dropped.
    @ObservationIgnored private var generation = 0

    static let framesPerSecond = 30.0

    init(
        build: @escaping Build,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.build = build
        self.sleep = sleep
    }

    /// Previews `joint` at `value`. One rebuild runs at a time; a newer value replaces one still waiting.
    func drive(_ joint: UUID, to value: Double, in document: CADDocument) {
        pending = (Self.document(document, driving: joint, to: value), joint, value)
        guard worker == nil else { return }
        let generation = generation
        worker = Task { [weak self] in
            while let self, self.generation == generation, let next = self.pending {
                self.pending = nil
                await self.show(next.document, next.joint, next.value, generation: generation)
            }
            if let self, self.generation == generation {
                self.worker = nil
            }
        }
    }

    /// Waits until the previews asked for so far are shown.
    func settle() async {
        await worker?.value
    }

    /// Sweeps `joint` through `range` at `rate` units per second and stops at its end, which stays as the preview.
    func animate(_ joint: UUID, in document: CADDocument, over range: ClosedRange<Double>, rate: Double) async {
        animation?.cancel()
        isAnimating = true
        let generation = generation
        let task = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            var frame = 0
            while !Task.isCancelled {
                let elapsed = start.duration(to: clock.now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
                let value = frame == 0 ? range.lowerBound : min(range.upperBound, range.lowerBound + rate * seconds)
                frame += 1
                guard let self else { return }
                await self.show(
                    Self.document(document, driving: joint, to: value), joint, value, generation: generation)
                if value >= range.upperBound {
                    return
                }
                try? await self.sleep(.seconds(1 / Self.framesPerSecond))
            }
        }
        animation = task
        await task.value
        if animation == task {
            animation = nil
            isAnimating = false
        }
    }

    /// Ends a running animation where it is.
    func stop() {
        animation?.cancel()
        animation = nil
        isAnimating = false
    }

    /// Drops the preview, so the document shows as it is.
    func clear() {
        stop()
        generation += 1
        pending = nil
        worker = nil
        preview = nil
        previewed = nil
    }

    private func show(_ document: CADDocument, _ joint: UUID, _ value: Double, generation: Int) async {
        let result = try? await build(document)
        guard let result, generation == self.generation else { return }
        preview = result
        previewed = (joint, value)
    }

    static func document(_ document: CADDocument, driving joint: UUID, to value: Double) -> CADDocument {
        var copy = document
        if let index = copy.joints.firstIndex(where: { $0.id == joint }) {
            copy.assembly?.joints[index].value = .number(value)
        }
        return copy
    }
}

/// The ranges the inspector drives a joint through.
enum JointMotionRange {
    /// The slider's range: the limits, or a full turn for a revolute without both limits; none for a travel without
    /// both limits.
    static func slider(_ result: JointResult) -> ClosedRange<Double>? {
        switch result.motion {
        case nil:
            return nil
        case .angle:
            let low = result.minimum ?? (result.maximum.map { $0 - 360 } ?? -180)
            let high = result.maximum ?? low + 360
            return low < high ? low...high : nil
        case .travel:
            guard let low = result.minimum, let high = result.maximum, low < high else { return nil }
            return low...high
        }
    }

    /// What Animate sweeps: the limits, or one turn up from the minimum (0° without one) for a revolute.
    static func sweep(_ result: JointResult) -> ClosedRange<Double>? {
        if let low = result.minimum, let high = result.maximum {
            return low < high ? low...high : nil
        }
        guard result.motion == .angle else { return nil }
        if let high = result.maximum {
            return (high - 360)...high
        }
        let low = result.minimum ?? 0
        return low...(low + 360)
    }

    /// Degrees or millimetres per second.
    static func rate(_ motion: JointMotion) -> Double {
        switch motion {
        case .angle: 60
        case .travel: 40
        }
    }
}
