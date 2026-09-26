import simd

/// A rotation about an axis through the origin followed by a translation, as a `Placement` describes it.
public struct RigidTransform: Sendable, Equatable {
    public var rotation: simd_double3x3
    public var translation: SIMD3<Double>

    public static let identity = RigidTransform(rotation: matrix_identity_double3x3, translation: .zero)

    public init(rotation: simd_double3x3, translation: SIMD3<Double>) {
        self.rotation = rotation
        self.translation = translation
    }

    public init(_ placement: ResolvedPlacement) {
        let length = simd_length(placement.rotationAxis)
        if length > 0, placement.rotationDegrees != 0 {
            let quaternion = simd_quatd(
                angle: placement.rotationDegrees * .pi / 180, axis: placement.rotationAxis / length
            )
            rotation = simd_double3x3(quaternion)
        } else {
            rotation = matrix_identity_double3x3
        }
        translation = placement.translation
    }

    public func point(_ p: SIMD3<Double>) -> SIMD3<Double> {
        rotation * p + translation
    }

    public func direction(_ d: SIMD3<Double>) -> SIMD3<Double> {
        rotation * d
    }

    func point(_ p: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(point(SIMD3<Double>(p)))
    }

    func direction(_ d: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(direction(SIMD3<Double>(d)))
    }
}

public extension BodyTopology {
    func transformed(by transform: RigidTransform) -> BodyTopology {
        BodyTopology(
            faces: faces.map { face in
                var face = face
                face.centroid = transform.point(face.centroid)
                face.normal = face.normal.map(transform.direction)
                face.axisOrigin = face.axisOrigin.map(transform.point)
                face.axis = face.axis.map(transform.direction)
                return face
            },
            edges: edges.map { edge in
                var edge = edge
                edge.start = transform.point(edge.start)
                edge.end = transform.point(edge.end)
                edge.midpoint = transform.point(edge.midpoint)
                edge.direction = edge.direction.map(transform.direction)
                edge.center = edge.center.map(transform.point)
                edge.axis = edge.axis.map(transform.direction)
                return edge
            }
        )
    }
}

public extension BodyMesh {
    func transformed(by transform: RigidTransform) -> BodyMesh {
        BodyMesh(
            positions: positions.map(transform.point), normals: normals.map(transform.direction), indices: indices
        )
    }
}

extension RigidTransform {
    /// `local` expressed in the coordinates this transform maps into.
    public func composed(with local: RigidTransform) -> RigidTransform {
        RigidTransform(rotation: rotation * local.rotation, translation: point(local.translation))
    }

    /// The same move as a rotation of `rotationDegrees` about `rotationAxis`, then the translation.
    public var resolvedPlacement: ResolvedPlacement {
        let quaternion = simd_quatd(rotation)
        let degrees = quaternion.angle * 180 / .pi
        let axis = quaternion.axis
        guard abs(degrees) > 1e-12, simd_length(axis) > 0.5 else { return ResolvedPlacement(translation: translation) }
        return ResolvedPlacement(translation: translation, rotationAxis: axis, rotationDegrees: degrees)
    }

    /// Whether the two transforms move points by no more than `tolerance` apart within a unit of the origin.
    func isClose(to other: RigidTransform, tolerance: Double = 1e-9) -> Bool {
        let columns = [0, 1, 2].map { simd_length(rotation[$0] - other.rotation[$0]) }
        return simd_length(translation - other.translation) <= tolerance && (columns.max() ?? 0) <= tolerance
    }
}
