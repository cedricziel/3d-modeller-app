import CADModel
import RealityKit
import SwiftUI

@MainActor
struct Viewport3DView: View {
    let result: RebuildResult?

    @State private var scene = ViewportScene()
    @State private var camera = OrbitCamera()
    @State private var cameraAtGestureStart: OrbitCamera?
    @State private var hasFramedModel = false
    @State private var cameraEntity: Entity = {
        let entity = Entity()
        entity.components.set(PerspectiveCameraComponent())
        return entity
    }()

    var body: some View {
        RealityView { content in
            content.add(scene.root)
            content.add(cameraEntity)
            aimCamera()
        } update: { _ in
            aimCamera()
        }
        .gesture(orbitGesture)
        .gesture(zoomGesture)
        .background(Color(white: 0.15))
        .onChange(of: result, initial: true) {
            scene.show(result)
            if !hasFramedModel, let bounds = ViewportFrame.sceneBounds(of: result) {
                camera = .framing(bounds)
                hasFramedModel = true
            }
        }
    }

    private func aimCamera() {
        cameraEntity.look(at: camera.target, from: camera.position, relativeTo: nil)
    }

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
}

#Preview {
    Viewport3DView(result: nil)
}
