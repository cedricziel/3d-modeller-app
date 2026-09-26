import simd

/// A joint's value and limits, evaluated, with what is wrong with them.
public struct JointDrive: Sendable, Equatable {
    public let motion: JointMotion?
    public let value: Double?
    public let minimum: Double?
    public let maximum: Double?
    /// Why the value or limits cannot be used; the joint then fails and is solved undriven.
    public let problem: String?

    public var isDriven: Bool {
        problem == nil && value != nil
    }

    public static func evaluate(_ joint: Joint, parameters: ParameterTable) -> JointDrive {
        let motion = joint.kind.motion
        func failed(_ problem: String, _ minimum: Double? = nil, _ maximum: Double? = nil) -> JointDrive {
            JointDrive(motion: motion, value: nil, minimum: minimum, maximum: maximum, problem: problem)
        }
        guard let motion else {
            if joint.value != nil {
                return failed("a \(joint.kind.rawValue) joint has no single motion to drive; remove its value")
            }
            if joint.limits != nil {
                return failed("a \(joint.kind.rawValue) joint has no single motion to limit; remove its limits")
            }
            return JointDrive(motion: nil, value: nil, minimum: nil, maximum: nil, problem: nil)
        }
        var numbers: [String: Double] = [:]
        for (field, scalar) in [
            ("limits.min", joint.limits?.min), ("limits.max", joint.limits?.max), ("value", joint.value),
        ] {
            guard let scalar else { continue }
            do {
                numbers[field] = try parameters.evaluate(scalar)
            } catch {
                return failed("\(field): \(error)")
            }
        }
        let (minimum, maximum, value) = (numbers["limits.min"], numbers["limits.max"], numbers["value"])
        if let minimum, let maximum, minimum > maximum {
            return failed(
                "limits min \(motion.format(minimum)) is above max \(motion.format(maximum))", minimum, maximum
            )
        }
        if let value, value < (minimum ?? -.infinity) || value > (maximum ?? .infinity) {
            return failed(
                "value \(motion.format(value)) is outside its limits \(range(motion, minimum, maximum))", minimum,
                maximum
            )
        }
        return JointDrive(motion: motion, value: value, minimum: minimum, maximum: maximum, problem: nil)
    }

    /// `min…max` in the motion's unit, with an open end as "…".
    public static func range(_ motion: JointMotion, _ minimum: Double?, _ maximum: Double?) -> String {
        "\(minimum.map(motion.format) ?? "")…\(maximum.map(motion.format) ?? "")"
    }

    /// The joint the solver gets: a driven motion is folded into side a's marker, leaving a stricter kind.
    func driven(_ kind: JointKind, markerA: RigidTransform) -> (kind: JointKind, markerA: RigidTransform) {
        guard isDriven, let value else { return (kind, markerA) }
        let along = RigidTransform(rotation: matrix_identity_double3x3, translation: SIMD3(0, 0, value))
        switch kind {
        case .revolute:
            let turn = simd_double3x3(simd_quatd(angle: value * .pi / 180, axis: SIMD3(0, 0, 1)))
            return (.fixed, markerA.composed(with: RigidTransform(rotation: turn, translation: .zero)))
        case .slider: return (.fixed, markerA.composed(with: along))
        case .cylindrical: return (.revolute, markerA.composed(with: along))
        case .fixed, .ball, .planar: return (kind, markerA)
        }
    }

    /// The motion's value between the world frames of a and b.
    func measure(a: RigidTransform, b: RigidTransform) -> Double? {
        switch motion {
        case nil:
            return nil
        case .travel:
            return simd_dot(b.translation - a.translation, a.rotation.columns.2)
        case .angle:
            let x = b.rotation.columns.0
            var degrees = atan2(simd_dot(x, a.rotation.columns.1), simd_dot(x, a.rotation.columns.0)) * 180 / .pi
            if let minimum {
                degrees -= ((degrees - minimum) / 360).rounded(.down) * 360
            } else if degrees <= -180 {
                degrees += 360
            }
            return degrees
        }
    }
}
