import CADModel
import SwiftUI

struct FeatureInspectorView: View {
    let feature: Feature?
    let result: FeatureResult?

    var body: some View {
        if let feature {
            Form {
                Section {
                    LabeledContent("Name", value: feature.name)
                    LabeledContent("Type", value: feature.kind.title)
                    if let body = result?.body { LabeledContent("Body", value: body) }
                    if let status = result?.status {
                        LabeledContent("Status") {
                            Label(status.description, systemImage: status.symbolName)
                                .foregroundStyle(status.tint)
                                .textSelection(.enabled)
                        }
                    }
                }
                Section("Parameters") {
                    ForEach(feature.kind.properties, id: \.self) { property in
                        LabeledContent(property.label, value: property.value)
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "No Selection", systemImage: "cube.transparent",
                description: Text("Select a feature in the outline to see its parameters"))
        }
    }
}
