import CADSolvers
import simd

enum AssemblyFixtures {
    static func rotation(axis: SIMD3<Double>, degrees: Double) -> simd_double3x3 {
        simd_double3x3(simd_quatd(angle: degrees * .pi / 180, axis: simd_normalize(axis)))
    }

    static func placement(
        _ x: Double, _ y: Double, _ z: Double, axis: SIMD3<Double> = SIMD3(0, 0, 1), degrees: Double = 0
    ) -> RigidPlacement {
        RigidPlacement(rotation: rotation(axis: axis, degrees: degrees), translation: SIMD3(x, y, z))
    }

    /// A grounded base at the origin whose joint marker sits at (0, 0, 10) with z up.
    static let baseMarker = placement(0, 0, 10)

    static func twoBodies(
        _ kind: AssemblyJointKind, start: RigidPlacement, markerB: RigidPlacement = .identity
    ) -> AssemblySystem {
        AssemblySystem(
            bodies: [AssemblyBody(placement: .identity, grounded: true), AssemblyBody(placement: start)],
            joints: [AssemblyJoint(kind, 0, baseMarker, 1, markerB)]
        )
    }

    /// The world frame of joint `index`'s side B after the solve.
    static func frameB(_ system: AssemblySystem, _ solution: AssemblySolution, joint index: Int = 0) -> RigidPlacement {
        let joint = system.joints[index]
        return solution.placements[joint.bodyB].composed(with: joint.markerB)
    }

    static func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ tolerance: Double = 1e-6) -> Bool {
        simd_distance(a, b) <= tolerance
    }

    static func close(_ a: simd_double3x3, _ b: simd_double3x3, _ tolerance: Double = 1e-6) -> Bool {
        simd_distance(a.columns.0, b.columns.0) <= tolerance && simd_distance(a.columns.1, b.columns.1) <= tolerance
            && simd_distance(a.columns.2, b.columns.2) <= tolerance
    }
}
