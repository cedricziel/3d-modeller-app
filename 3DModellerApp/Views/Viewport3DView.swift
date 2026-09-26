import SwiftUI
import RealityKit

/// 3D viewport using RealityKit
@MainActor
struct Viewport3DView: View {
    @ObservedObject var sceneManager: SceneManager
    @EnvironmentObject private var appModel: AppModel

    @State private var camera = OrbitCamera()
    @State private var cameraAtGestureStart: OrbitCamera?
    @State private var cameraEntity: Entity = {
        let entity = Entity()
        entity.components.set(PerspectiveCameraComponent())
        return entity
    }()

    // Track if scene is ready
    @State private var isSceneReady = false

    var body: some View {
        GeometryReader { _ in
            if isSceneReady {
                RealityView { content in
                    content.add(sceneManager.rootEntity)
                    content.add(cameraEntity)
                    aimCamera()
                } update: { _ in
                    aimCamera()
                }
                .gesture(orbitGesture)
                .gesture(zoomGesture)
                .gesture(tapGesture)
            } else {
                Color(white: 0.15)
                    .overlay {
                        ProgressView("Loading 3D Scene...")
                    }
            }
        }
        .background(Color(white: 0.15))
        .task {
            // Delay to allow UI to render first
            try? await Task.sleep(for: .milliseconds(100))
            isSceneReady = true
        }
    }

    // MARK: - Camera

    private func aimCamera() {
        cameraEntity.look(at: .zero, from: camera.position, relativeTo: nil)
    }

    // MARK: - Gestures

    private var orbitGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = cameraAtGestureStart ?? camera
                cameraAtGestureStart = start
                camera = start.orbited(by: value.translation)
            }
            .onEnded { _ in
                cameraAtGestureStart = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = cameraAtGestureStart ?? camera
                cameraAtGestureStart = start
                camera = start.zoomed(by: value.magnification)
            }
            .onEnded { _ in
                cameraAtGestureStart = nil
            }
    }

    /// Tap to select entities
    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                // For now, deselect on tap
                // Entity selection requires hit testing which is more complex in RealityView
                sceneManager.select(id: nil)
            }
    }
}

// MARK: - Entity Selection Highlight

extension Viewport3DView {
    /// Update visual selection state
    private func updateSelectionHighlight() {
        // Remove highlight from all entities
        for cadEntity in sceneManager.entities.values {
            // Reset to original material
        }

        // Add highlight to selected entity
        if let selectedId = sceneManager.selectedEntityId,
            let cadEntity = sceneManager.entities[selectedId]
        {
            // Apply selection highlight material
        }
    }
}

#Preview {
    Viewport3DView(sceneManager: SceneManager())
        .environmentObject(AppModel())
}
