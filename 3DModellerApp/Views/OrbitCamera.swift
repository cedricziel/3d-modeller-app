import CoreGraphics
import simd

/// A camera orbiting the scene origin, described by distance and pitch/yaw angles in radians
struct OrbitCamera: Equatable {
    static let distanceRange: ClosedRange<Float> = 1...20
    static let pitchLimit: Float = .pi / 2 - 0.1
    static let dragSensitivity: Float = 0.01

    var distance: Float = 5
    var pitch: Float = .pi / 6
    var yaw: Float = .pi / 4

    var position: SIMD3<Float> {
        SIMD3(
            distance * cos(pitch) * sin(yaw),
            distance * sin(pitch),
            distance * cos(pitch) * cos(yaw)
        )
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
