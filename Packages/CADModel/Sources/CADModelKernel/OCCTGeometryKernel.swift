import CADKernel
import CADModel

public struct OCCTGeometryKernel: GeometryKernel {
    public typealias Body = Solid

    public var tessellationTolerance: Double

    public init(tessellationTolerance: Double = 0.05) {
        self.tessellationTolerance = tessellationTolerance
    }

    public func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement, feature: String)
        throws -> Solid
    {
        try Kernel.box(
            width: width, depth: depth, height: height, placement: CADKernel.Placement(placement), feature: feature)
    }

    public func cylinder(radius: Double, height: Double, placement: ResolvedPlacement, feature: String) throws
        -> Solid
    {
        try Kernel.cylinder(radius: radius, height: height, placement: CADKernel.Placement(placement), feature: feature)
    }

    public func sphere(radius: Double, placement: ResolvedPlacement, feature: String) throws -> Solid {
        try Kernel.sphere(radius: radius, placement: CADKernel.Placement(placement), feature: feature)
    }

    public func cone(
        bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement, feature: String
    ) throws -> Solid {
        try Kernel.cone(
            bottomRadius: bottomRadius, topRadius: topRadius, height: height,
            placement: CADKernel.Placement(placement), feature: feature)
    }

    public func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement, feature: String) throws
        -> Solid
    {
        try Kernel.torus(
            majorRadius: majorRadius, minorRadius: minorRadius, placement: CADKernel.Placement(placement),
            feature: feature)
    }

    public func boolean(_ operation: CADModel.BooleanOperation, _ target: Solid, _ tool: Solid, feature: String)
        throws -> Solid
    {
        let kernelOperation: CADKernel.BooleanOperation =
            switch operation {
            case .union: .union
            case .subtract: .subtract
            case .intersect: .intersect
            }
        return try Kernel.boolean(kernelOperation, target, tool, feature: feature)
    }

    public func transform(_ body: Solid, by placement: ResolvedPlacement) throws -> Solid {
        try Kernel.transform(body, by: CADKernel.Placement(placement))
    }

    public func fillet(_ body: Solid, edges: [Int], radius: Double, feature: String) throws -> Solid {
        try Kernel.fillet(body, edges: edges, radius: radius, feature: feature)
    }

    public func chamfer(_ body: Solid, edges: [Int], distance: Double, feature: String) throws -> Solid {
        try Kernel.chamfer(body, edges: edges, distance: distance, feature: feature)
    }

    public func shell(_ body: Solid, faces: [Int], thickness: Double, feature: String) throws -> Solid {
        try Kernel.shell(body, removing: faces, thickness: thickness, feature: feature)
    }

    public func topology(of body: Solid) throws -> BodyTopology {
        let topology = try Kernel.topology(of: body)
        return BodyTopology(
            faces: topology.faces.map { face in
                FaceDescriptor(
                    names: face.names, surface: CADModel.SurfaceKind(rawValue: face.surface.rawValue) ?? .other,
                    centroid: face.centroid, area: face.area, normal: face.normal, axisOrigin: face.axisOrigin,
                    axis: face.axis, radius: face.radius)
            },
            edges: topology.edges.map { edge in
                EdgeDescriptor(
                    faces: edge.faces, curve: CADModel.CurveKind(rawValue: edge.curve.rawValue) ?? .other,
                    length: edge.length, start: edge.start, end: edge.end, midpoint: edge.midpoint,
                    direction: edge.direction, center: edge.center, axis: edge.axis, radius: edge.radius)
            })
    }

    public func metrics(of body: Solid) throws -> BodyMetrics {
        let metrics = try Kernel.metrics(of: body)
        return BodyMetrics(
            volume: metrics.volume, boundsMin: metrics.boundsMin, boundsMax: metrics.boundsMax,
            faceCount: metrics.faceCount, solidCount: metrics.solidCount,
            isValid: metrics.isValid, isClosed: metrics.isClosed)
    }

    public func mesh(of body: Solid) throws -> BodyMesh {
        let mesh = try Kernel.tessellate(body, tolerance: tessellationTolerance)
        return BodyMesh(positions: mesh.positions, normals: mesh.normals, indices: mesh.indices)
    }
}

extension CADKernel.Placement {
    init(_ placement: ResolvedPlacement) {
        self.init(
            translation: placement.translation,
            axis: placement.rotationAxis,
            angle: placement.rotationDegrees * .pi / 180
        )
    }
}
