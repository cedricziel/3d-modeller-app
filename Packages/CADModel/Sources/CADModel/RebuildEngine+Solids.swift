public struct BuiltBody<Body: Sendable>: Sendable {
    public let part: String
    public let name: String
    public let body: Body
}

extension RebuildEngine {
    /// The final body shapes of every part, for callers that combine bodies further.
    @concurrent
    public func solids(of document: CADDocument) async throws -> [BuiltBody<Kernel.Body>] {
        let parameters = ParameterTable(document.parameters)
        var solids: [BuiltBody<Kernel.Body>] = []
        for part in document.parts {
            var builder = PartBuilder(kernel: kernel, sketchSolver: sketchSolver, parameters: parameters)
            for feature in part.features {
                try Task.checkCancellation()
                _ = builder.apply(feature)
            }
            solids += builder.builtBodies.map { BuiltBody(part: part.name, name: $0.name, body: $0.body) }
        }
        return solids
    }
}
