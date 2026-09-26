import OCCTSwift
import simd

extension Kernel {
    /// Sweeps the profile's regions along the plane normal from offset `from` to offset `to` (mm). Faces are named
    /// `<feature>.start` (at `from`), `<feature>.end` (at `to`) and `<feature>.side[<curve name>]`.
    public static func extrude(_ profile: Profile, from: Double, to: Double, feature: String) throws -> Solid {
        guard from.isFinite, to.isFinite, from != to else {
            throw KernelError.invalidDimensions("the extrusion needs two different, finite offsets")
        }
        let normal = profile.plane.normal
        let sweep = ProfileNaming.Sweep(
            move: { point, fraction in point + (from + fraction * (to - from)) * normal }, normal: { _ in normal },
            hasCaps: true)
        return try sweepRegions(
            profile, on: profile.plane.offset(by: from), sweep: sweep, feature: feature,
            operation: "extrude the profile"
        ) { face in
            face.extruded(by: (to - from) * normal)
        }
    }

    /// Revolves the profile's regions by `angle` radians (0 < angle ≤ 2π) about the axis, counter-clockwise about
    /// its direction. A partial revolution has `<feature>.start` in the profile plane and `<feature>.end` where it
    /// stops; every swept face is `<feature>.side[<curve name>]`.
    public static func revolve(
        _ profile: Profile, axisOrigin: SIMD3<Double>, axisDirection: SIMD3<Double>, angle: Double, feature: String
    ) throws -> Solid {
        let values = [axisOrigin.x, axisOrigin.y, axisOrigin.z, axisDirection.x, axisDirection.y, axisDirection.z]
        guard values.allSatisfy(\.isFinite), simd_length(axisDirection) > 1e-12 else {
            throw KernelError.invalidDimensions("the axis must be finite and have a direction")
        }
        guard angle.isFinite, angle > 0, angle <= 2 * .pi + 1e-12 else {
            throw KernelError.invalidDimensions("the angle must be greater than 0 and at most one full turn")
        }
        let axis = simd_normalize(axisDirection)
        let full = angle >= 2 * .pi - 1e-12
        let normal = profile.plane.normal
        let sweep = ProfileNaming.Sweep(
            move: { point, fraction in
                axisOrigin + simd_quatd(angle: fraction * angle, axis: axis).act(point - axisOrigin)
            },
            normal: { fraction in simd_quatd(angle: fraction * angle, axis: axis).act(normal) }, hasCaps: !full)
        return try sweepRegions(
            profile, on: profile.plane, sweep: sweep, feature: feature, operation: "revolve the profile"
        ) { face in
            full
                ? face.revolved(axisOrigin: axisOrigin, axisDirection: axis)
                : face.revolved(axisOrigin: axisOrigin, axisDirection: axis, angle: angle)
        }
    }

    private static func regionFaces(_ regions: [ProfileRegion], on plane: ProfilePlane) throws -> [Shape] {
        guard !regions.isEmpty else { throw KernelError.invalidDimensions("the profile has no closed region") }
        return try regions.map { region in
            let outer = try wire(region.outer, on: plane)
            let holes = try region.holes.map { try wire($0, on: plane) }
            guard let face = holes.isEmpty ? Shape.face(from: outer) : Shape.face(outer: outer, holes: holes),
                face.isValid
            else {
                throw KernelError.operationFailed("build a face from the profile")
            }
            return face
        }
    }

    private static func wire(_ loop: [ProfileCurve], on plane: ProfilePlane) throws -> Wire {
        let pieces = try loop.map { curve -> Wire in
            let piece: Wire? =
                switch curve.geometry {
                case .line(let a, let b): Wire.line(from: plane.point(a), to: plane.point(b))
                case .arc(_, _, let start, let mid, let end):
                    Wire.arc(start: plane.point(start), midpoint: plane.point(mid), end: plane.point(end))
                case .circle(let center, let radius):
                    Wire.circle(origin: plane.point(center), normal: plane.normal, radius: radius)
                }
            guard let piece else { throw KernelError.operationFailed("build the profile curve \(curve.name)") }
            return piece
        }
        guard let joined = pieces.count == 1 ? pieces[0] : Wire.join(pieces) else {
            throw KernelError.operationFailed("join the profile curves into a loop")
        }
        return joined
    }

    /// Sweeps each region on its own, names its faces, and fuses the pieces, so loops that cross or touch give
    /// one solid rather than overlapping ones.
    private static func sweepRegions(
        _ profile: Profile, on plane: ProfilePlane, sweep: ProfileNaming.Sweep, feature: String, operation: String,
        _ make: (Shape) -> Shape?
    ) throws -> Solid {
        return try OCCTSerial.withLock {
            let faces = try regionFaces(profile.regions, on: plane)
            var pieces: [Solid] = []
            for (region, face) in zip(profile.regions, faces) {
                guard let shape = make(face), shape.isValid, let volume = shape.volume, volume > 0 else {
                    throw KernelError.operationFailed(operation)
                }
                let names = ProfileNaming.names(
                    of: shape, profile: Profile(plane: profile.plane, regions: [region]), sweep: sweep,
                    feature: feature)
                pieces.append(Solid(shape: shape, faceNames: names))
            }
            var result = pieces[0]
            for piece in pieces.dropFirst() { result = try boolean(.union, result, piece, feature: feature) }
            return result
        }
    }
}
