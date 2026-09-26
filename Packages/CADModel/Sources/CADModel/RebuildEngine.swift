public struct RebuiltModel: Sendable {
    public let result: RebuildResult
    /// Measurements on the bodies of `result`.
    public let geometry: ModelGeometry
}

public struct RebuildEngine<Kernel: GeometryKernel>: Sendable {
    public let kernel: Kernel
    public let sketchSolver: (any SketchSolving)?

    /// Without a sketch solver every sketch fails, and the features that use one are skipped.
    public init(kernel: Kernel, sketchSolver: (any SketchSolving)? = nil) {
        self.kernel = kernel
        self.sketchSolver = sketchSolver
    }

    @concurrent
    public func rebuild(_ document: CADDocument) async throws -> RebuildResult {
        try await build(document).result
    }

    /// Rebuilds the document and keeps its bodies for measuring.
    @concurrent
    public func build(_ document: CADDocument) async throws -> RebuiltModel {
        let parameters = ParameterTable(document.parameters)
        var parts: [PartResult] = []
        var bodies: [BodyKey: Kernel.Body] = [:]
        for part in document.parts {
            var builder = PartBuilder(kernel: kernel, sketchSolver: sketchSolver, parameters: parameters)
            var features: [FeatureResult] = []
            for feature in part.features {
                try Task.checkCancellation()
                features.append(builder.apply(feature))
            }
            parts.append(
                PartResult(
                    id: part.id, name: part.name, features: features, bodies: try builder.bodyResults(),
                    sketches: builder.sketchResults))
            for (name, body) in builder.builtBodies {
                bodies[BodyKey(part: part.id, body: name)] = body
            }
        }
        try Task.checkCancellation()
        return RebuiltModel(
            result: RebuildResult(parameters: parameters, parts: parts),
            geometry: ModelGeometry(kernel: kernel, bodies: bodies))
    }
}
