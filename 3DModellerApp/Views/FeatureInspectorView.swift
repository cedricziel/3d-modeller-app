import CADModel
import SwiftUI

struct FeatureInspectorView: View {
    let feature: Feature?
    let result: FeatureResult?
    var sketch: SketchResult?
    /// The part the feature belongs to.
    var part: Part?
    var setPartAppearance: ((Appearance?) -> Void)?

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
                if let part, let setPartAppearance {
                    AppearanceSection(
                        title: "Part \(part.name)", appearance: part.appearance, inherited: nil,
                        clearLabel: "Use Default Colours", set: setPartAppearance)
                }
                Section("Parameters") {
                    ForEach(feature.kind.properties, id: \.self) { property in
                        LabeledContent(property.label, value: property.value)
                    }
                }
                if case .sketch(let stored) = feature.kind {
                    SketchInspectorSections(stored: stored, solved: sketch)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "No Selection", systemImage: "cube.transparent",
                description: Text("Select a feature or instance in the outline to see its details"))
        }
    }
}

private struct SketchInspectorSections: View {
    let stored: SketchFeature
    let solved: SketchResult?

    var body: some View {
        Section("Solve") {
            LabeledContent("State", value: solved?.state.description ?? "Not solved")
            if let open = solved?.profiles.openEnds, !open.isEmpty {
                LabeledContent("Open ends", value: open.joined(separator: ", "))
            }
        }
        Section("Entities") {
            ForEach(solved?.entities ?? stored.entities, id: \.name) { entity in
                LabeledContent(entity.name, value: entity.label)
            }
        }
        Section("Constraints") {
            ForEach(stored.constraints, id: \.name) { constraint in
                LabeledContent(constraint.name, value: constraint.label)
            }
        }
    }
}
