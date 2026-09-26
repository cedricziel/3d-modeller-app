public enum ViewDirection: String, CaseIterable, Sendable {
    case iso, top, front, right

    /// Screen right, screen up and the direction the camera looks, in model coordinates (Z up).
    var basis: (right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>) {
        switch self {
        case .top: (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, -1))
        case .front: (SIMD3(1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0))
        case .right: (SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(-1, 0, 0))
        case .iso:
            (
                SIMD3(1, 1, 0) / Float(2).squareRoot(), SIMD3(-1, 1, 2) / Float(6).squareRoot(),
                SIMD3(-1, 1, -1) / Float(3).squareRoot()
            )
        }
    }

    var caption: String {
        switch self {
        case .iso: "iso: seen from +X −Y +Z, Z up"
        case .top: "top: looking down −Z, +X right, +Y up"
        case .front: "front: looking along +Y at the −Y side, +X right, +Z up"
        case .right: "right: looking along −X at the +X side, +Y right, +Z up"
        }
    }
}
