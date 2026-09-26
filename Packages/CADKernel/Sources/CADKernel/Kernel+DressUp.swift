import OCCTSwift

extension Kernel {
    public static func fillet(_ solid: Solid, edges: [Int], radius: Double, feature: String) throws -> Solid {
        try requirePositive(radius, "radius")
        return try OCCTSerial.withLock {
            let edgeShapes = try selected(edges, of: solid.shape, type: .edge, noneMatched: .noEdgesMatched)
            guard let (result, history) = solid.shape.filletedWithFullHistory(radius: radius, edges: edges) else {
                throw KernelError.operationFailed("fillet the selected edges")
            }
            return try finish(
                result, "fillet the selected edges", solid, history, feature: feature, edges: edgeShapes,
                generatedFromEdge: { "\(feature).face[\($0)]" })
        }
    }

    public static func chamfer(_ solid: Solid, edges: [Int], distance: Double, feature: String) throws -> Solid {
        try requirePositive(distance, "distance")
        return try OCCTSerial.withLock {
            let edgeShapes = try selected(edges, of: solid.shape, type: .edge, noneMatched: .noEdgesMatched)
            guard let (result, history) = solid.shape.chamferedWithFullHistory(distance: distance, edges: edges)
            else {
                throw KernelError.operationFailed("chamfer the selected edges")
            }
            return try finish(
                result, "chamfer the selected edges", solid, history, feature: feature, edges: edgeShapes,
                generatedFromEdge: { "\(feature).face[\($0)]" })
        }
    }

    /// Hollows the solid, leaving walls `thickness` thick inside its outline, open where `faces` were.
    public static func shell(_ solid: Solid, removing faces: [Int], thickness: Double, feature: String) throws -> Solid
    {
        try requirePositive(thickness, "thickness")
        return try OCCTSerial.withLock {
            _ = try selected(faces, of: solid.shape, type: .face, noneMatched: .noFacesMatched)
            guard
                let (result, history) = solid.shape.shelledWithFullHistory(
                    facesToRemove: faces, thickness: -thickness)
            else {
                throw KernelError.operationFailed("shell the solid")
            }
            // OCCT returns a valid-looking but wrong solid when the walls would meet; a real shell keeps every
            // original face and only removes material.
            guard let before = solid.shape.volume, let after = result.volume, after > 0, after < before,
                result.faceCount > solid.shape.faceCount
            else {
                throw KernelError.operationFailed("shell the solid; the walls are too thick for it")
            }
            return try finish(
                result, "shell the solid", solid, history, feature: feature,
                generatedFromFace: { "\(feature).inner[\($0)]" })
        }
    }

    private static func requirePositive(_ value: Double, _ name: String) throws {
        guard value.isFinite, value > 0 else {
            throw KernelError.invalidDimensions("\(name) must be greater than 0")
        }
    }

    private static func selected(
        _ indices: [Int], of shape: Shape, type: ShapeType, noneMatched: KernelError
    ) throws -> [Shape] {
        guard !indices.isEmpty else { throw noneMatched }
        let all = shape.subShapes(ofType: type)
        let noun = type == .edge ? "edge" : "face"
        if let bad = indices.first(where: { !all.indices.contains($0) }) {
            throw KernelError.invalidDimensions("\(noun) \(bad) does not exist; the solid has \(all.count) \(noun)s")
        }
        return indices.map { all[$0] }
    }

    private static func finish(
        _ result: Shape, _ operation: String, _ input: Solid, _ history: ShapeHistoryRef, feature: String,
        edges: [Shape] = [], generatedFromEdge: ((Int) -> String)? = nil,
        generatedFromFace: ((String) -> String)? = nil
    ) throws -> Solid {
        guard result.isValid, result.solidCount > 0 else { throw KernelError.operationFailed(operation) }
        let names = Naming.carry(
            [.init(shape: input.shape, names: input.faceNames)], into: result, history: history, feature: feature,
            edges: edges, generatedFromEdge: generatedFromEdge, generatedFromFace: generatedFromFace)
        return Solid(shape: result, faceNames: names)
    }
}
