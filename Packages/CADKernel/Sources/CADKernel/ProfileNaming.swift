import OCCTSwift
import simd

/// Names the faces of a swept profile from their geometry, since OCCT keeps no history for prisms and revolutions.
/// Each profile curve's midpoint is carried along the sweep: the planar face perpendicular to the sweep that holds
/// it where the sweep starts is `.start`, where it stops `.end`, and the face that holds it halfway is
/// `.side[<curve name>]`.
enum ProfileNaming {
    static let tolerance = 1e-6

    struct Sweep {
        /// Where a point of the profile plane is after `fraction` of the sweep (0 at the start, 1 at the end).
        let move: (SIMD3<Double>, Double) -> SIMD3<Double>
        /// The normal of the profile plane after `fraction` of the sweep.
        let normal: (Double) -> SIMD3<Double>
        let hasCaps: Bool
    }

    static func names(of shape: Shape, profile: Profile, sweep: Sweep, feature: String) -> [[String]] {
        let solid = Solid(shape: shape, feature: feature)
        guard let topology = try? Kernel.topology(of: solid) else {
            return Naming.fallback(solid.faceNames.count, feature: feature)
        }
        var names = [[String]](repeating: [], count: topology.faces.count)
        func faces(holding point: SIMD3<Double>) -> [Int] {
            topology.faces.indices.filter { index in
                ((try? Kernel.distance(from: point, to: solid, .face(index)))?.value ?? .infinity) <= tolerance
            }
        }
        func isCap(_ index: Int, fraction: Double) -> Bool {
            guard topology.faces[index].surface == .plane, let normal = topology.faces[index].normal else {
                return false
            }
            return abs(abs(simd_dot(normal, sweep.normal(fraction))) - 1) <= 1e-9
        }
        for curve in profile.curves {
            let point = profile.plane.point(curve.geometry.midpoint)
            if sweep.hasCaps {
                for (fraction, role) in [(0.0, "start"), (1.0, "end")] {
                    for index in faces(holding: sweep.move(point, fraction))
                    where names[index].isEmpty && isCap(index, fraction: fraction) {
                        names[index] = ["\(feature).\(role)"]
                    }
                }
            }
            for index in faces(holding: sweep.move(point, 0.5)) where names[index].isEmpty {
                names[index] = ["\(feature).side[\(curve.name)]"]
            }
        }
        return Naming.fillGaps(names, feature: feature)
    }
}

extension ProfileGeometry {
    /// A point on the curve away from its ends.
    var midpoint: SIMD2<Double> {
        switch self {
        case .line(let a, let b): (a + b) / 2
        case .arc(_, _, _, let mid, _): mid
        case .circle(let center, let radius): center + SIMD2(radius, 0)
        }
    }
}
