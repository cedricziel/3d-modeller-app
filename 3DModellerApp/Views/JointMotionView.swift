import CADModel
import SwiftUI

/// Drives a joint: a slider previews values while it moves and commits one undo step on release; Animate sweeps the
/// joint through its range as a preview, which Keep commits.
struct JointMotionView: View {
    let joint: Joint
    let result: JointResult
    let document: CADDocument
    let driver: JointDriver
    /// Sets the joint's value in the document as one undo step.
    let commit: (Double) -> Void

    @State private var dragged: Double?
    @State private var typed: Double?

    private var motion: JointMotion {
        result.motion ?? .angle
    }

    private var previewValue: Double? {
        driver.previewed.flatMap { $0.joint == joint.id ? $0.value : nil }
    }

    private var shownValue: Double? {
        dragged ?? previewValue ?? result.value
    }

    var body: some View {
        Section("Motion") {
            LabeledContent("Value") {
                Text(shownValue.map(motion.format) ?? "—")
                    + Text(previewValue != nil ? "  preview" : result.driven ? "  driven" : "  free")
                    .foregroundStyle(.secondary)
            }
            if result.minimum != nil || result.maximum != nil {
                LabeledContent("Limits", value: JointDrive.range(motion, result.minimum, result.maximum))
            }
            LabeledContent("Freedoms", value: "\(result.freedoms) dof")
            if let range = JointMotionRange.slider(result) {
                Slider(
                    value: Binding(
                        get: { min(max(shownValue ?? range.lowerBound, range.lowerBound), range.upperBound) },
                        set: { value in
                            dragged = value
                            driver.drive(joint.id, to: value, in: document)
                        }
                    ),
                    in: range
                ) { editing in
                    guard !editing, let value = dragged else { return }
                    commit(value)
                }
                .disabled(driver.isAnimating)
            }
            TextField("Set value", value: $typed, format: .number)
                .onSubmit {
                    guard let value = typed, value >= (result.minimum ?? -.infinity),
                        value <= (result.maximum ?? .infinity)
                    else { return }
                    commit(value)
                    typed = nil
                }
            HStack {
                if driver.isAnimating {
                    Button("Stop") { driver.stop() }
                } else if let sweep = JointMotionRange.sweep(result) {
                    Button("Animate") {
                        Task {
                            await driver.animate(
                                joint.id, in: document, over: sweep, rate: JointMotionRange.rate(motion)
                            )
                        }
                    }
                }
                if let value = previewValue, !driver.isAnimating, dragged == nil {
                    Button("Keep \(motion.format(value))") { commit(value) }
                    Button("Reset") { driver.clear() }
                }
            }
        }
        .onChange(of: result) { dragged = nil }
    }
}
