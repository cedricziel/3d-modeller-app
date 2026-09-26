import Foundation

public struct BuiltBody<Body: Sendable>: Sendable {
    /// The part's name, or for an instance solid the instance's name.
    public let part: String
    public let name: String
    public let body: Body
}

extension RebuildEngine {
    /// The final body shapes of every part, for callers that combine bodies further.
    @concurrent
    public func solids(of document: CADDocument) async throws -> [BuiltBody<Kernel.Body>] {
        try partBodies(of: document).flatMap { part, bodies in
            bodies.map { BuiltBody(part: part.name, name: $0.name, body: $0.body) }
        }
    }

    /// Each placed instance's moved bodies, in assembly order; instances that fail to place are left out.
    @concurrent
    public func instanceSolids(of document: CADDocument) async throws -> [BuiltBody<Kernel.Body>] {
        guard let assembly = document.assembly else { return [] }
        let built = try partBodies(of: document)
        let builder = AssemblyBuilder(
            kernel: kernel, parameters: ParameterTable(document.parameters), parts: document.parts,
            partBodies: Dictionary(built.map { ($0.part.id, $0.bodies) }, uniquingKeysWith: { first, _ in first }))
        return try builder.place(assembly).flatMap { instance, outcome in
            guard case .success(let placed) = outcome else { return [BuiltBody<Kernel.Body>]() }
            return placed.bodies.map { BuiltBody(part: instance.name, name: $0.name, body: $0.body) }
        }
    }

    private func partBodies(of document: CADDocument) throws -> [(
        part: Part, bodies: [(name: String, body: Kernel.Body)]
    )] {
        let parameters = ParameterTable(document.parameters)
        return try document.parts.map { part in
            var builder = PartBuilder(kernel: kernel, sketchSolver: sketchSolver, parameters: parameters)
            for feature in part.features {
                try Task.checkCancellation()
                _ = builder.apply(feature)
            }
            return (part, builder.builtBodies)
        }
    }
}
