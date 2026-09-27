import CADModel
import SwiftUI

/// Shows an appearance and lets the user pick its colour or remove it.
struct AppearanceSection: View {
    let title: String
    let appearance: Appearance?
    /// What shows when `appearance` is nil, such as the part's appearance for an instance.
    let inherited: Appearance?
    let clearLabel: String
    let set: (Appearance?) -> Void

    var body: some View {
        Section(title) {
            ColorPicker(selection: colour, supportsOpacity: false) {
                LabeledContent("Colour", value: shown?.color.hex ?? "Default")
            }
            if let metallic = shown?.metallic {
                LabeledContent("Metallic", value: metallic.formatted())
            }
            if let roughness = shown?.roughness {
                LabeledContent("Roughness", value: roughness.formatted())
            }
            if appearance != nil {
                Button(clearLabel) { set(nil) }
            }
        }
    }

    private var shown: Appearance? {
        appearance ?? inherited
    }

    private var colour: Binding<Color> {
        Binding(
            get: { shown.map { Color($0.color) } ?? .gray },
            set: { picked in
                guard let hex = HexColor(picked), hex != shown?.color else { return }
                set(appearance?.with(color: hex) ?? inherited?.with(color: hex) ?? Appearance(color: hex))
            }
        )
    }
}

/// What an appearance edit in the inspector changes.
enum AppearanceTarget: Equatable {
    case part(UUID)
    case instance(UUID)

    func name(in document: CADDocument) -> String {
        switch self {
        case .part(let id): document.part(id: id)?.name ?? "part"
        case .instance(let id): document.instances.first { $0.id == id }?.name ?? "instance"
        }
    }

    func apply(_ appearance: Appearance?, to document: inout CADDocument) {
        switch self {
        case .part(let id):
            guard let index = document.parts.firstIndex(where: { $0.id == id }) else { return }
            document.parts[index].appearance = appearance
        case .instance(let id):
            guard let index = document.instances.firstIndex(where: { $0.id == id }) else { return }
            document.assembly?.instances[index].appearance = appearance
        }
    }
}
