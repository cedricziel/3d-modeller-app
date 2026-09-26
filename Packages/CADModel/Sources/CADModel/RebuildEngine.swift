import Foundation

public struct RebuiltModel: Sendable {
    public let result: RebuildResult
    /// Measurements on the bodies of `result`.
    public let geometry: ModelGeometry
}

public struct RebuildEngine<Kernel: GeometryKernel>: Sendable {
    public let kernel: Kernel
    public let sketchSolver: (any SketchSolving)?
    public let assemblySolver: (any AssemblySolving)?

    /// Without a sketch solver every sketch fails, and the features that use one are skipped. Without an assembly
    /// solver every joint fails, and the instances stay at their placements.
    public init(
        kernel: Kernel, sketchSolver: (any SketchSolving)? = nil, assemblySolver: (any AssemblySolving)? = nil
    ) {
        self.kernel = kernel
        self.sketchSolver = sketchSolver
        self.assemblySolver = assemblySolver
    }

    @concurrent
    public func rebuild(_ document: CADDocument) async throws -> RebuildResult {
        try await build(document).result
    }

    /// Rebuilds the document and keeps its bodies for measuring.
    @concurrent
    public func build(_ document: CADDocument) async throws -> RebuiltModel {
        try await assemble(document).model
    }

    /// The rebuild, with each placed instance's bodies where the joints put them.
    @concurrent
    func assemble(_ document: CADDocument) async throws -> (
        model: RebuiltModel, instances: [(instance: Instance, bodies: [(name: String, body: Kernel.Body)])]
    ) {
        let parameters = ParameterTable(document.parameters)
        var parts: [PartResult] = []
        var bodies: [BodyKey: Kernel.Body] = [:]
        var partBodies: [UUID: [(name: String, body: Kernel.Body)]] = [:]
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
            partBodies[part.id] = builder.builtBodies
            for (name, body) in builder.builtBodies {
                bodies[BodyKey(part: part.id, body: name)] = body
            }
        }
        var assembly: AssemblyResult?
        var instanceBodies: [(instance: Instance, bodies: [(name: String, body: Kernel.Body)])] = []
        if let documentAssembly = document.assembly {
            let builder = AssemblyBuilder(
                kernel: kernel, parameters: parameters, parts: document.parts, partBodies: partBodies)
            let assembled = try builder.assemble(
                documentAssembly,
                partResults: Dictionary(parts.map { ($0.id, $0.bodies) }, uniquingKeysWith: { first, _ in first }),
                solver: assemblySolver)
            assembly = assembled.result
            instanceBodies = assembled.bodies
            for (instance, placed) in assembled.bodies {
                for (name, body) in placed {
                    bodies[BodyKey(owner: .instance(instance.id), body: name)] = body
                }
            }
        }
        try Task.checkCancellation()
        let model = RebuiltModel(
            result: RebuildResult(parameters: parameters, parts: parts, assembly: assembly),
            geometry: ModelGeometry(kernel: kernel, bodies: bodies))
        return (model, instanceBodies)
    }
}
