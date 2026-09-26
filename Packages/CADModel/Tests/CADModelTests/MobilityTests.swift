@testable import CADModel
import simd
import Testing

@Suite("Mobility")
struct MobilityTests {
    private static func frame(at origin: SIMD3<Double>) -> RigidTransform {
        RigidTransform(rotation: matrix_identity_double3x3, translation: origin)
    }

    private static func joint(_ kind: JointKind, _ a: Int, _ b: Int, at origin: SIMD3<Double>) -> MobilityJoint {
        MobilityJoint(kind: kind, bodyA: a, bodyB: b, a: frame(at: origin), b: frame(at: origin))
    }

    @Test("A body joined to the ground keeps the freedoms its joint's kind leaves", arguments: JointKind.allCases)
    func singleJoint(kind: JointKind) {
        let freedoms = Mobility.freedoms(
            bodies: 2, grounded: [0], joints: [Self.joint(kind, 0, 1, at: SIMD3(3, 40, 7))]
        )
        #expect(freedoms == [0, kind.freedoms])
    }

    @Test("Two hinges in series with parallel axes leave the second link two freedoms")
    func chain() {
        let joints = [
            Self.joint(.revolute, 0, 1, at: SIMD3(0, 0, 0)), Self.joint(.revolute, 1, 2, at: SIMD3(50, 0, 0)),
        ]
        #expect(Mobility.freedoms(bodies: 3, grounded: [0], joints: joints) == [0, 1, 2])
    }

    @Test("A revolute and a cylindrical joint on one axis leave one freedom, not zero")
    func redundantPair() {
        let joints = [
            Self.joint(.revolute, 0, 1, at: SIMD3(1, 2, 3)), Self.joint(.cylindrical, 0, 1, at: SIMD3(1, 2, 3)),
        ]
        #expect(Mobility.freedoms(bodies: 2, grounded: [0], joints: joints) == [0, 1])
    }

    @Test("A parallelogram four-bar moves with one freedom per link, although counting gives fewer than none")
    func fourBar() {
        let joints = [
            Self.joint(.revolute, 0, 1, at: SIMD3(0, 0, 0)), Self.joint(.revolute, 1, 2, at: SIMD3(0, 20, 0)),
            Self.joint(.revolute, 2, 3, at: SIMD3(40, 20, 0)), Self.joint(.revolute, 3, 0, at: SIMD3(40, 0, 0)),
        ]
        #expect(Mobility.freedoms(bodies: 4, grounded: [0], joints: joints) == [0, 1, 1, 1])
    }

    @Test("Bodies joined only to each other float freely")
    func island() {
        let joints = [Self.joint(.revolute, 1, 2, at: SIMD3(5, 5, 5))]
        #expect(Mobility.freedoms(bodies: 3, grounded: [0], joints: joints) == [0, 6, 6])
    }

    @Test("A slider along a tilted axis leaves one freedom")
    func tiltedSlider() {
        let tilt = simd_double3x3(simd_quatd(angle: 0.7, axis: simd_normalize(SIMD3(1, 1, 0))))
        let frame = RigidTransform(rotation: tilt, translation: SIMD3(100, -30, 12))
        let joint = MobilityJoint(kind: .slider, bodyA: 0, bodyB: 1, a: frame, b: frame)
        #expect(Mobility.freedoms(bodies: 2, grounded: [0], joints: [joint]) == [0, 1])
    }
}
