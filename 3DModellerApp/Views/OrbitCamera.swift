import CoreGraphics
import simd

/// A camera orbiting `target`, described by distance and pitch/yaw angles in radians
struct OrbitCamera: Equatable {
    static let distanceRange: ClosedRange<Float> = 0.05...50
    static let pitchLimit: Float = .pi / 2 - 0.1
    static let dragSensitivity: Float = 0.01

    var target: SIMD3<Float> = .zero
    var distance: Float = 0.4
    var pitch: Float = .pi / 6
    var yaw: Float = .pi / 4

    var position: SIMD3<Float> {
        target
            + SIMD3(
                distance * cos(pitch) * sin(yaw),
                distance * sin(pitch),
                distance * cos(pitch) * cos(yaw)
            )
    }

    static func framing(_ bounds: SceneBounds?) -> OrbitCamera {
        var camera = OrbitCamera()
        guard let bounds else { return camera }
        camera.target = (bounds.min + bounds.max) / 2
        let size = simd_length(bounds.max - bounds.min)
        camera.distance = min(max(size * 1.8, distanceRange.lowerBound), distanceRange.upperBound)
        return camera
    }

    static func framing(min: SIMD3<Float>, max: SIMD3<Float>) -> OrbitCamera {
        framing(SceneBounds(min: min, max: max))
    }

    func orbited(by translation: CGSize) -> OrbitCamera {
        var camera = self
        camera.yaw -= Float(translation.width) * Self.dragSensitivity
        camera.pitch -= Float(translation.height) * Self.dragSensitivity
        camera.pitch = min(max(camera.pitch, -Self.pitchLimit), Self.pitchLimit)
        return camera
    }

    func zoomed(by magnification: CGFloat) -> OrbitCamera {
        var camera = self
        let range = Self.distanceRange
        camera.distance = min(max(distance / Float(magnification), range.lowerBound), range.upperBound)
        return camera
    }
}
