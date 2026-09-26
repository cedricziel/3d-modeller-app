import CADModel
import SwiftUI

struct FeatureOutlineView: View {
    let model: CADDocument
    let result: RebuildResult?
    @Binding var selection: UUID?
    let setSuppressed: (Feature, Bool) -> Void
    let delete: (Feature) -> Void

    var body: some View {
        List(selection: $selection) {
            if !model.parameters.isEmpty {
                Section("Parameters") {
                    ForEach(Array(model.parameters.enumerated()), id: \.offset) { _, parameter in
                        ParameterRow(parameter: parameter, value: result?.parameters.value(of: parameter.name))
                    }
                }
            }
            ForEach(model.parts) { part in
                Section(part.name) {
                    if part.features.isEmpty {
                        Text("No features").foregroundStyle(.secondary).italic()
                    }
                    ForEach(part.features) { feature in
                        FeatureRow(feature: feature, result: result?.feature(id: feature.id))
                            .tag(feature.id)
                            .contextMenu {
                                Button(feature.suppressed ? "Unsuppress" : "Suppress") {
                                    setSuppressed(feature, !feature.suppressed)
                                }
                                Divider()
                                Button("Delete", role: .destructive) { delete(feature) }
                            }
                    }
                }
            }
            if let assembly = model.assembly {
                Section("Assembly") {
                    if assembly.instances.isEmpty {
                        Text("No instances").foregroundStyle(.secondary).italic()
                    }
                    ForEach(assembly.instances) { instance in
                        InstanceRow(
                            instance: instance, partName: model.part(id: instance.part)?.name,
                            result: result?.assembly?.instance(id: instance.id)
                        )
                        .tag(instance.id)
                    }
                    ForEach(assembly.joints) { joint in
                        JointRow(joint: joint, model: model, result: result?.assembly?.joint(id: joint.id))
                            .tag(joint.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct ParameterRow: View {
    let parameter: Parameter
    let value: Result<Double, ExpressionError>?

    var body: some View {
        HStack {
            Text(parameter.name)
            Spacer()
            switch value {
            case .success(let number)?:
                Text(Scalar.number(number).description).foregroundStyle(.secondary).monospacedDigit()
            case .failure(let error)?:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).help(error.description)
            case nil:
                EmptyView()
            }
        }
        .help("\(parameter.name) = \(parameter.expression)")
    }
}

private struct FeatureRow: View {
    let feature: Feature
    let result: FeatureResult?

    var body: some View {
        HStack {
            Image(systemName: feature.kind.symbolName).frame(width: 20).foregroundStyle(.secondary)
            Text(feature.name).lineLimit(1).strikethrough(feature.suppressed)
            Spacer()
            if let status = result?.status {
                Image(systemName: status.symbolName).foregroundStyle(status.tint).help(status.description)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

private struct InstanceRow: View {
    let instance: Instance
    let partName: String?
    let result: InstanceResult?

    var body: some View {
        HStack {
            Image(systemName: instance.grounded ? "pin.fill" : "shippingbox").frame(width: 20).foregroundStyle(
                .secondary)
            Text(instance.name).lineLimit(1)
            Text(partName ?? "missing part").foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let status = result?.status {
                Image(systemName: status.symbolName).foregroundStyle(status.tint).help(status.description)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

private struct JointRow: View {
    let joint: Joint
    let model: CADDocument
    let result: JointResult?

    var body: some View {
        HStack {
            Image(systemName: joint.kind.symbolName).frame(width: 20).foregroundStyle(.secondary)
            Text(joint.name).lineLimit(1)
            Text("\(model.instanceName(joint.a.instance)) ↔ \(model.instanceName(joint.b.instance))")
                .foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let status = result?.status {
                Image(systemName: status.symbolName).foregroundStyle(status.tint).help(status.description)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .help("\(joint.kind.label) joint")
    }
}
