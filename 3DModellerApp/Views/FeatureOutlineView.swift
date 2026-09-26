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
