public struct RebuiltModel: Sendable {
    public let result: RebuildResult
    /// Measurements on the bodies of `result`.
    public let geometry: ModelGeometry
}

public struct RebuildEngine<Kernel: GeometryKernel>: Sendable {
    public let kernel: Kernel

    public init(kernel: Kernel) {
        self.kernel = kernel
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
            var builder = PartBuilder(kernel: kernel, parameters: parameters)
            var features: [FeatureResult] = []
            for feature in part.features {
                try Task.checkCancellation()
                features.append(builder.apply(feature))
            }
            parts.append(
                PartResult(id: part.id, name: part.name, features: features, bodies: try builder.bodyResults()))
            for (name, body) in builder.builtBodies {
                bodies[BodyKey(part: part.name, body: name)] = body
            }
        }
        try Task.checkCancellation()
        return RebuiltModel(
            result: RebuildResult(parameters: parameters, parts: parts),
            geometry: ModelGeometry(kernel: kernel, bodies: bodies))
    }
}
