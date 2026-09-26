import OCCTSwift

public enum Kernel {
    public static func extrudeRectangle(width: Double, height: Double, depth: Double) throws -> Solid {
        guard width > 0, height > 0, depth > 0 else {
            throw KernelError.invalidDimensions("width, height and depth must be greater than 0")
        }
        return try OCCTSerial.withLock {
            guard let profile = Wire.rectangle(width: width, height: height),
                let shape = Shape.extrude(profile: profile, direction: SIMD3(0, 0, 1), length: depth),
                shape.isValid
            else {
                throw KernelError.operationFailed("extrude the rectangle")
            }
            return Solid(shape: shape)
        }
    }

    public static func metrics(of solid: Solid) throws -> SolidMetrics {
        try OCCTSerial.withLock {
            let shape = solid.shape
            guard let bounds = shape.boundingBox else {
                throw KernelError.operationFailed("measure the solid")
            }
            let solids = shape.solids
            return SolidMetrics(
                volume: shape.volume,
                boundsMin: bounds.min,
                boundsMax: bounds.max,
                faceCount: shape.faceCount,
                edgeCount: shape.edgeCount,
                solidCount: solids.count,
                isValid: shape.isValid,
                isClosed: !solids.isEmpty && solids.allSatisfy(\.isValidSolid)
                    && shape.freeBounds(sewingTolerance: 0) == nil
            )
        }
    }

    public static func fillet(_ solid: Solid, edges query: EdgeQuery, radius: Double) throws -> Solid {
        guard radius > 0 else {
            throw KernelError.invalidDimensions("radius must be greater than 0")
        }
        return try OCCTSerial.withLock {
            let edges = query.edges(of: solid.shape)
            guard !edges.isEmpty else { throw KernelError.noEdgesMatched }
            guard let shape = solid.shape.filleted(edges: edges, radius: radius), shape.isValid else {
                throw KernelError.operationFailed("fillet the selected edges")
            }
            return Solid(shape: shape)
        }
    }

    public static func tessellate(_ solid: Solid, tolerance: Double = 0.001) throws -> KernelMesh {
        try OCCTSerial.withLock {
            guard let mesh = solid.shape.mesh(linearDeflection: tolerance, angularDeflection: 0.5) else {
                throw KernelError.operationFailed("tessellate the solid")
            }
            return KernelMesh(positions: mesh.vertices, indices: mesh.indices)
        }
    }
}
