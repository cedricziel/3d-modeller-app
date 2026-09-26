import SwiftUI

/// Sidebar showing scene entity hierarchy
@MainActor
struct SceneOutlineView: View {
    @ObservedObject var sceneManager: SceneManager

    var body: some View {
        List(
            selection: Binding(
                get: { sceneManager.selectedEntityId },
                set: { sceneManager.select(id: $0) }
            )
        ) {
            Section("Objects") {
                if sceneManager.entities.isEmpty {
                    Text("No objects in scene")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(sortedEntities, id: \.id) { entity in
                        EntityRow(entity: entity, isSelected: entity.id == sceneManager.selectedEntityId)
                            .tag(entity.id)
                            .contextMenu {
                                entityContextMenu(for: entity)
                            }
                    }
                    .onDelete(perform: deleteEntities)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Helpers

    private var sortedEntities: [CADEntity] {
        sceneManager.entities.values.sorted { $0.name < $1.name }
    }

    private func deleteEntities(at offsets: IndexSet) {
        let entities = sortedEntities
        for index in offsets {
            _ = sceneManager.deleteEntity(id: entities[index].id)
        }
    }

    @ViewBuilder
    private func entityContextMenu(for entity: CADEntity) -> some View {
        Button("Duplicate") {
            _ = sceneManager.duplicateEntity(id: entity.id)
        }

        Divider()

        Button("Delete", role: .destructive) {
            _ = sceneManager.deleteEntity(id: entity.id)
        }
    }
}

// MARK: - Entity Row

@MainActor
struct EntityRow: View {
    let entity: CADEntity
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: iconName(for: entity.type))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 20)

            Text(entity.name)
                .lineLimit(1)

            Spacer()
        }
        .contentShape(Rectangle())
    }

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

#Preview {
    SceneOutlineView(sceneManager: SceneManager())
}
