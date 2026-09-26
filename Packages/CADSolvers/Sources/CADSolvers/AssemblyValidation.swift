import simd

extension RigidPlacement {
    /// Why this is not a finite rigid placement, or nil.
    var problem: String? {
        let columns = [rotation.columns.0, rotation.columns.1, rotation.columns.2]
        guard (columns + [translation]).allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            return "has a non-finite number"
        }
        let product = rotation.transpose * rotation
        let identity = matrix_identity_double3x3
        let deviation = [0, 1, 2].map { simd_length(product[$0] - identity[$0]) }.max() ?? 0
        guard deviation <= 1e-9 else { return "has a rotation that is not orthonormal" }
        guard simd_determinant(rotation) > 0 else { return "has a rotation that mirrors" }
        return nil
    }
}

extension AssemblySystem {
    func validate() throws(AssemblySolverError) {
        for (index, body) in bodies.enumerated() {
            if let problem = body.placement.problem {
                throw .invalidBody(index: index, reason: "the placement \(problem)")
            }
        }
        for (index, joint) in joints.enumerated() {
            for body in [joint.bodyA, joint.bodyB] where !bodies.indices.contains(body) {
                throw .invalidJoint(index: index, reason: "body \(body) does not exist")
            }
            guard joint.bodyA != joint.bodyB else {
                throw .invalidJoint(index: index, reason: "both sides are body \(joint.bodyA)")
            }
            for marker in [joint.markerA, joint.markerB] {
                if let problem = marker.problem { throw .invalidJoint(index: index, reason: "a marker \(problem)") }
            }
        }
        if !joints.isEmpty, !bodies.contains(where: \.grounded) { throw .nothingGrounded }
    }
}
