import simd

enum JointCheck {
    static let distanceTolerance = 1e-6
    /// About 1 − cos θ ≤ 1e-9.
    static let angleTolerance = 4.5e-5

    /// The joint's state judged from the world frames of its markers, ignoring what the solver reported.
    static func state(_ kind: AssemblyJointKind, _ a: RigidPlacement, _ b: RigidPlacement) -> JointState {
        let offset = b.translation - a.translation
        let z = a.rotation.columns.2
        let zAngle = angle(z, b.rotation.columns.2)
        let xAngle = angle(a.rotation.columns.0, b.rotation.columns.0)
        let alongAxis = offset - simd_dot(offset, z) * z
        let (distance, worstAngle): (Double, Double) =
            switch kind {
            case .fixed: (simd_length(offset), max(zAngle, xAngle))
            case .revolute: (simd_length(offset), zAngle)
            case .slider: (simd_length(alongAxis), max(zAngle, xAngle))
            case .cylindrical: (simd_length(alongAxis), zAngle)
            case .ball: (simd_length(offset), 0)
            case .planar: (abs(simd_dot(offset, z)), zAngle)
            }
        guard distance <= distanceTolerance, worstAngle <= angleTolerance else {
            return .unsatisfied(distance: distance, angle: worstAngle)
        }
        return .satisfied
    }

    private static func angle(_ u: SIMD3<Double>, _ v: SIMD3<Double>) -> Double {
        atan2(simd_length(simd_cross(u, v)), simd_dot(u, v))
    }
}
