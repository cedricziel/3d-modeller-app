import COndselSolver
import simd

/// Owns one OndselSolver assembly through the C shim; not shared across threads.
final class OndselSystem {
    struct JointReport {
        let constraints: Int
        let redundant: Int
    }

    private let handle: OpaquePointer

    init() throws(AssemblySolverError) {
        guard let handle = os_create() else { throw .solverFailure("could not create an OndselSolver assembly") }
        self.handle = handle
    }

    deinit {
        os_destroy(handle)
    }

    func addBody(_ placement: RigidPlacement, grounded: Bool) throws(AssemblySolverError) {
        try check(os_add_body(handle, Self.c(placement), grounded ? 1 : 0))
    }

    func addJoint(_ kind: AssemblyJointKind, _ a: Int, _ markerA: RigidPlacement, _ b: Int, _ markerB: RigidPlacement)
        throws(AssemblySolverError)
    {
        try check(os_add_joint(handle, Self.code(kind), Int32(a), Self.c(markerA), Int32(b), Self.c(markerB)))
    }

    func solve() throws(AssemblySolverError) {
        try check(os_solve(handle))
    }

    func placement(ofBody index: Int) throws(AssemblySolverError) -> RigidPlacement {
        var placement = OSPlacement()
        try check(os_body_placement(handle, Int32(index), &placement))
        return Self.swift(placement)
    }

    func report(ofJoint index: Int) throws(AssemblySolverError) -> JointReport {
        var report = OSJointReport()
        try check(os_joint_report(handle, Int32(index), &report))
        return JointReport(constraints: Int(report.constraints), redundant: Int(report.redundant))
    }

    private func check(_ result: Int32) throws(AssemblySolverError) {
        guard result < 0 else { return }
        throw .solverFailure(String(cString: os_last_error(handle)))
    }

    private static func code(_ kind: AssemblyJointKind) -> Int32 {
        let code =
            switch kind {
            case .fixed: OS_FIXED
            case .revolute: OS_REVOLUTE
            case .slider: OS_SLIDER
            case .cylindrical: OS_CYLINDRICAL
            case .ball: OS_BALL
            case .planar: OS_PLANAR
            }
        return Int32(code)
    }

    private static func c(_ placement: RigidPlacement) -> OSPlacement {
        let m = placement.rotation
        let t = placement.translation
        return OSPlacement(
            rotation: (
                m[0][0], m[1][0], m[2][0],
                m[0][1], m[1][1], m[2][1],
                m[0][2], m[1][2], m[2][2]
            ),
            translation: (t.x, t.y, t.z))
    }

    private static func swift(_ placement: OSPlacement) -> RigidPlacement {
        let r = placement.rotation
        let t = placement.translation
        let rotation = simd_double3x3(rows: [SIMD3(r.0, r.1, r.2), SIMD3(r.3, r.4, r.5), SIMD3(r.6, r.7, r.8)])
        return RigidPlacement(rotation: rotation, translation: SIMD3(t.0, t.1, t.2))
    }
}
