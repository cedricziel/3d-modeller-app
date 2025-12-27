import SwiftUI

/// Inspector panel showing properties of selected entity
struct PropertiesInspectorView: View {
    @ObservedObject var sceneManager: SceneManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let entity = sceneManager.selectedEntity {
                    selectedEntityView(entity)
                } else {
                    noSelectionView
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - No Selection

    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Selection")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Select an object to view its properties")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Selected Entity

    @ViewBuilder
    private func selectedEntityView(_ entity: CADEntity) -> some View {
        // Header
        HStack {
            Image(systemName: iconName(for: entity.type))
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading) {
                Text(entity.name)
                    .font(.headline)

                Text(entity.type.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.bottom, 8)

        Divider()

        // Transform Section
        transformSection(entity)

        Divider()

        // Material Section
        materialSection(entity)

        Spacer()
    }

    // MARK: - Transform Section

    @ViewBuilder
    private func transformSection(_ entity: CADEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transform")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                PropertyRow(label: "Position") {
                    HStack {
                        VectorField(
                            x: entity.entity.position.x,
                            y: entity.entity.position.y,
                            z: entity.entity.position.z
                        ) { x, y, z in
                            _ = sceneManager.transformEntity(id: entity.id, position: [x, y, z])
                        }
                    }
                }

                PropertyRow(label: "Scale") {
                    HStack {
                        VectorField(
                            x: entity.entity.scale.x,
                            y: entity.entity.scale.y,
                            z: entity.entity.scale.z
                        ) { x, y, z in
                            _ = sceneManager.transformEntity(id: entity.id, scale: [x, y, z])
                        }
                    }
                }
            }
        }
    }

    // MARK: - Material Section

    @ViewBuilder
    private func materialSection(_ entity: CADEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Material")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                PropertyRow(label: "Color") {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: {
                                Color(
                                    red: Double(entity.material.color.r),
                                    green: Double(entity.material.color.g),
                                    blue: Double(entity.material.color.b)
                                )
                            },
                            set: { newColor in
                                let components = newColor.cgColor?.components ?? [0.8, 0.8, 0.8, 1.0]
                                let colorData = ColorData(
                                    r: Float(components[0]),
                                    g: Float(components[1]),
                                    b: Float(components[2]),
                                    a: Float(components.count > 3 ? components[3] : 1.0)
                                )
                                _ = sceneManager.setMaterial(id: entity.id, color: colorData)
                            }
                        )
                    )
                    .labelsHidden()
                }

                PropertyRow(label: "Metallic") {
                    Slider(
                        value: Binding(
                            get: { Double(entity.material.metallic) },
                            set: { _ = sceneManager.setMaterial(id: entity.id, metallic: Float($0)) }
                        ),
                        in: 0...1
                    )
                }

                PropertyRow(label: "Roughness") {
                    Slider(
                        value: Binding(
                            get: { Double(entity.material.roughness) },
                            set: { _ = sceneManager.setMaterial(id: entity.id, roughness: Float($0)) }
                        ),
                        in: 0...1
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func iconName(for type: EntityData.EntityType) -> String {
        switch type {
        case .box: return "cube"
        case .sphere: return "circle"
        case .cylinder: return "cylinder"
        case .cone: return "cone"
        case .plane: return "rectangle"
        case .torus: return "circle.circle"
        case .capsule: return "capsule"
        case .imported: return "doc.badge.plus"
        case .group: return "folder"
        }
    }
}

// MARK: - Property Row

struct PropertyRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            content()
        }
    }
}

// MARK: - Vector Field

struct VectorField: View {
    let x: Float
    let y: Float
    let z: Float
    let onChange: (Float, Float, Float) -> Void

    @State private var xValue: String = ""
    @State private var yValue: String = ""
    @State private var zValue: String = ""

    var body: some View {
        HStack(spacing: 4) {
            ComponentField(label: "X", value: x) { newX in
                onChange(newX, y, z)
            }

            ComponentField(label: "Y", value: y) { newY in
                onChange(x, newY, z)
            }

            ComponentField(label: "Z", value: z) { newZ in
                onChange(x, y, newZ)
            }
        }
    }
}

struct ComponentField: View {
    let label: String
    let value: Float
    let onChange: (Float) -> Void

    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 50)
                .onAppear {
                    text = String(format: "%.2f", value)
                }
                .onChange(of: value) { _, newValue in
                    text = String(format: "%.2f", newValue)
                }
                .onSubmit {
                    if let newValue = Float(text) {
                        onChange(newValue)
                    }
                }
        }
    }
}

#Preview {
    PropertiesInspectorView(sceneManager: SceneManager())
        .frame(width: 280)
}
