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
            guard let volume = solid.shape.volume, let bounds = solid.shape.boundingBox else {
                throw KernelError.operationFailed("measure the solid")
            }
            return SolidMetrics(
                volume: volume,
                boundsMin: bounds.min,
                boundsMax: bounds.max,
                edgeCount: solid.shape.edgeCount,
                isValid: solid.shape.isValid
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
}
