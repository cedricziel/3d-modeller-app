import SwiftUI
import RealityKit

/// 3D viewport using RealityKit
struct Viewport3DView: View {
    @ObservedObject var sceneManager: SceneManager
    @EnvironmentObject private var appModel: AppModel

    // Camera state
    @State private var cameraDistance: Float = 5.0
    @State private var cameraRotation: SIMD2<Float> = [Float.pi / 6, Float.pi / 4] // pitch, yaw

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                // Add the scene root entity
                content.add(sceneManager.rootEntity)

                // Setup camera anchor
                let cameraAnchor = AnchorEntity(world: .zero)
                content.add(cameraAnchor)
            } update: { _ in
                // Camera updates handled by gestures
            }
            .gesture(orbitGesture)
            .gesture(zoomGesture)
            .gesture(tapGesture)
            .onAppear {
                // Initial camera setup
            }
        }
        .background(Color(white: 0.15))
    }

    // MARK: - Camera Update

    private func updateCamera() {
        // Calculate camera position from spherical coordinates
        // Note: RealityView handles camera automatically in SwiftUI
        // This is a placeholder for future camera manipulation
    }

    // MARK: - Gestures

    /// Orbit camera with two-finger drag
    private var orbitGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let sensitivity: Float = 0.01
                cameraRotation.y += Float(value.translation.width) * sensitivity
                cameraRotation.x -= Float(value.translation.height) * sensitivity

                // Clamp pitch to avoid gimbal lock
                cameraRotation.x = max(-Float.pi / 2 + 0.1, min(Float.pi / 2 - 0.1, cameraRotation.x))
            }
    }

    /// Zoom with magnification gesture
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let scale = Float(value.magnification)
                cameraDistance = max(1.0, min(20.0, cameraDistance / scale))
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
           let cadEntity = sceneManager.entities[selectedId] {
            // Apply selection highlight material
        }
    }
}

#Preview {
    Viewport3DView(sceneManager: SceneManager())
        .environmentObject(AppModel())
}
