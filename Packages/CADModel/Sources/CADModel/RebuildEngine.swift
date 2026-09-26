public struct RebuildEngine<Kernel: GeometryKernel>: Sendable {
    public let kernel: Kernel

    public init(kernel: Kernel) {
        self.kernel = kernel
    }

    @concurrent
    public func rebuild(_ document: CADDocument) async throws -> RebuildResult {
        let parameters = ParameterTable(document.parameters)
        var parts: [PartResult] = []
        for part in document.parts {
            var builder = PartBuilder(kernel: kernel, parameters: parameters)
            var features: [FeatureResult] = []
            for feature in part.features {
                try Task.checkCancellation()
                features.append(builder.apply(feature))
            }
            parts.append(
                PartResult(id: part.id, name: part.name, features: features, bodies: try builder.bodyResults()))
        }
        try Task.checkCancellation()
        return RebuildResult(parameters: parameters, parts: parts)
    }
}
