import CADModel

/// How far a joint has moved, its limits and the freedoms it leaves, for the listing and write reports.
enum JointMotionText {
    /// For example "at 90° driven, limits 0°…110°, 0 dof"; nil when there is nothing to say, as for a fixed joint.
    static func describe(_ joint: Joint, _ result: JointResult?) -> String? {
        let motion = joint.kind.motion
        var parts: [String] = []
        if let result, let motion, let value = result.value {
            let outside = !result.driven && result.isOutsideLimits ? " (outside limits)" : ""
            parts.append("at \(motion.format(value)) \(result.driven ? "driven" : "free")\(outside)")
        } else if let motion, let value = joint.value {
            parts.append("driven to \(value)\(motion.unit)")
        }
        if let motion, let limits = joint.limits {
            if let result, result.minimum != nil || result.maximum != nil {
                parts.append("limits \(JointDrive.range(motion, result.minimum, result.maximum))")
            } else {
                let low = limits.min.map { "\($0)\(motion.unit)" } ?? ""
                let high = limits.max.map { "\($0)\(motion.unit)" } ?? ""
                parts.append("limits \(low)…\(high)")
            }
        }
        if let result, motion != nil || result.freedoms > 0 { parts.append("\(result.freedoms) dof") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// What an instance's result says about how it can still move, after its status.
    static func freedoms(_ instance: Instance, _ result: InstanceResult?) -> String {
        guard !instance.grounded, let freedoms = result?.freedoms else { return "" }
        return freedoms == 0 ? ", fully constrained" : ", \(freedoms) dof free"
    }
}
