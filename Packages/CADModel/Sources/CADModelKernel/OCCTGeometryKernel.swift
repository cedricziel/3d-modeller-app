import CADKernel
import CADModel

public struct OCCTGeometryKernel: GeometryKernel {
    public typealias Body = Solid

    public var tessellationTolerance: Double

    public init(tessellationTolerance: Double = 0.05) {
        self.tessellationTolerance = tessellationTolerance
    }

    public func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement) throws -> Solid {
        try Kernel.box(width: width, depth: depth, height: height, placement: CADKernel.Placement(placement))
    }

    public func cylinder(radius: Double, height: Double, placement: ResolvedPlacement) throws -> Solid {
        try Kernel.cylinder(radius: radius, height: height, placement: CADKernel.Placement(placement))
    }

    public func sphere(radius: Double, placement: ResolvedPlacement) throws -> Solid {
        try Kernel.sphere(radius: radius, placement: CADKernel.Placement(placement))
    }

    public func cone(bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement) throws
        -> Solid
    {
        try Kernel.cone(
            bottomRadius: bottomRadius, topRadius: topRadius, height: height, placement: CADKernel.Placement(placement))
    }

    public func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement) throws -> Solid {
        try Kernel.torus(majorRadius: majorRadius, minorRadius: minorRadius, placement: CADKernel.Placement(placement))
    }

    public func boolean(_ operation: CADModel.BooleanOperation, _ target: Solid, _ tool: Solid) throws -> Solid {
        let kernelOperation: CADKernel.BooleanOperation =
            switch operation {
            case .union: .union
            case .subtract: .subtract
            case .intersect: .intersect
            }
        return try Kernel.boolean(kernelOperation, target, tool)
    }

    public func transform(_ body: Solid, by placement: ResolvedPlacement) throws -> Solid {
        try Kernel.transform(body, by: CADKernel.Placement(placement))
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
