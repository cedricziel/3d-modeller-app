import OCCTSwift

public enum Kernel {
    public static func metrics(of solid: Solid) throws -> SolidMetrics {
        try OCCTSerial.withLock {
            let shape = solid.shape
            guard let bounds = shape.boundingBoxOptimal() else {
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

    public static func tessellate(_ solid: Solid, tolerance: Double = 0.001) throws -> KernelMesh {
        try OCCTSerial.withLock {
            guard let mesh = solid.shape.mesh(linearDeflection: tolerance, angularDeflection: 0.5) else {
                throw KernelError.operationFailed("tessellate the solid")
            }
            return KernelMesh(positions: mesh.vertices, indices: mesh.indices)
        }
    }
}
