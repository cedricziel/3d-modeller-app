import simd

public struct Placement: Sendable, Hashable, Codable {
    public var translation: SIMD3<Double>
    public var axis: SIMD3<Double>
    public var angle: Double

    public init(translation: SIMD3<Double> = .zero, axis: SIMD3<Double> = SIMD3(0, 0, 1), angle: Double = 0) {
        self.translation = translation
        self.axis = axis
        self.angle = angle
    }

    public static let identity = Placement()

    var rotation: simd_double3x3 {
        simd_double3x3(simd_quatd(angle: angle, axis: simd_normalize(axis)))
    }
}
