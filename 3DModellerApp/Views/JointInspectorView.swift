import CADModel
import SwiftUI

/// Details of an assembly joint, and the controls that drive it.
struct JointInspectorView: View {
    let joint: Joint
    let model: CADDocument
    let result: JointResult?
    let driver: JointDriver
    /// Drives the joint to a value in the document, as one undo step.
    let move: (Double) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: joint.name)
                LabeledContent("Kind", value: joint.kind.label)
                LabeledContent("Flipped", value: joint.flip ? "Yes" : "No")
                if let status = result?.status {
                    LabeledContent("Status") {
                        Label(status.description, systemImage: status.symbolName)
                            .foregroundStyle(status.tint)
                            .textSelection(.enabled)
                    }
                }
            }
            if let result, result.motion != nil {
                JointMotionView(joint: joint, result: result, document: model, driver: driver, commit: move)
            }
            side("Side A", joint.a)
            side("Side B", joint.b)
        }
        .formStyle(.grouped)
    }

    private func side(_ title: String, _ side: JointFrameRef) -> some View {
        Section(title) {
            LabeledContent("Instance", value: model.instanceName(side.instance))
            if let body = side.body { LabeledContent("Body", value: body) }
            LabeledContent("Face", value: side.face.description).textSelection(.enabled)
            if let edge = side.edge { LabeledContent("Edge", value: edge.description).textSelection(.enabled) }
            if let offset = side.offset {
                LabeledContent("Offset", value: "(\(offset.x), \(offset.y), \(offset.z)) mm, \(offset.angle)°")
            }
        }
    }
}

extension CADDocument {
    func instanceName(_ id: UUID) -> String {
        instances.first { $0.id == id }?.name ?? "Missing instance"
    }
}

extension JointKind {
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var symbolName: String {
        switch self {
        case .fixed: "lock"
        case .revolute: "arrow.triangle.2.circlepath"
        case .slider: "arrow.left.and.right"
        case .cylindrical: "cylinder"
        case .ball: "circle.circle"
        case .planar: "square.stack"
        }
    }
}

extension JointStatus {
    var symbolName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .redundant: "checkmark.circle.badge.questionmark"
        case .failed: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ok: .green
        case .redundant: .yellow
        case .failed: .red
        }
    }
}
