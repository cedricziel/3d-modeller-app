import CADModel
import SwiftUI

/// Details of an assembly instance; only its appearance can be changed here.
struct InstanceInspectorView: View {
    let instance: Instance
    let partName: String?
    let result: InstanceResult?
    var partAppearance: Appearance?
    var setAppearance: ((Appearance?) -> Void)?

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: instance.name)
                LabeledContent("Part", value: partName ?? "Missing part")
                LabeledContent("Body", value: instance.body ?? "All bodies")
                LabeledContent("Grounded", value: instance.grounded ? "Yes" : "No")
                if let status = result?.status {
                    LabeledContent("Status") {
                        Label(status.description, systemImage: status.symbolName)
                            .foregroundStyle(status.tint)
                            .textSelection(.enabled)
                    }
                }
            }
            if let setAppearance {
                AppearanceSection(
                    title: "Appearance", appearance: instance.appearance, inherited: partAppearance,
                    clearLabel: "Use Part's Appearance", set: setAppearance)
            }
            Section("Placement") {
                ForEach(instance.placement.properties, id: \.self) { property in
                    LabeledContent(property.label, value: property.value)
                }
            }
            if let bounds = result?.boundsLabel {
                Section("Where it is") {
                    LabeledContent("Bounds", value: bounds).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension InstanceStatus {
    var symbolName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ok: .green
        case .failed: .red
        }
    }
}

extension InstanceResult {
    /// The bounds of all its bodies in assembly coordinates, in mm.
    var boundsLabel: String? {
        let metrics = bodies.compactMap(\.metrics)
        guard let first = metrics.first else { return nil }
        let low = metrics.dropFirst().reduce(first.boundsMin) { pointwiseMin($0, $1.boundsMin) }
        let high = metrics.dropFirst().reduce(first.boundsMax) { pointwiseMax($0, $1.boundsMax) }
        func point(_ p: SIMD3<Double>) -> String {
            "(\(Scalar.number(p.x)), \(Scalar.number(p.y)), \(Scalar.number(p.z)))"
        }
        return "\(point(low)) to \(point(high))"
    }
}
