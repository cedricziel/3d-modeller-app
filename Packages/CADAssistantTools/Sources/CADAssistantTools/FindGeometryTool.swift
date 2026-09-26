import CADModel
import SwiftUIAssistant

public struct FindGeometryTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "find_geometry"

    public let description = """
        Lists the faces or edges of a body with the names that fillet, chamfer and shell accept, each with its type, \
        centre, normal or axis, radius, and area or length (mm). A filter narrows the list, for example \
        "normal +Z", "parallel Z and farthest +X", "circular r=2.75" or "on Plate.top"; without one every face or \
        edge is listed. Faces are named after the feature and role that made them (Plate.top, Hole.side, \
        Fillet1.face[0]); pieces of a split face get [0], [1]. Edges are named by their two faces: \
        edge(Plate.front, Plate.top).
        """

    public var parameters: [ToolParameter] {
        [
            ToolSchemas.part,
            .optionalString(
                "instance", description: "An assembly instance instead of a part; positions are where it is placed."),
            .optionalString(
                "body", description: "The body, such as Body1. Optional for an instance whose part has one body."),
            .enumParameter("kind", description: "faces or edges.", values: GeometryKind.allCases.map(\.rawValue)),
            .optionalString(
                "filter",
                description: """
                    Faces: normal +Z, parallel X, perpendicular Y, type plane|cylinder|cone|sphere|torus|other, \
                    circular [r=2.75], farthest +X. Edges: parallel Z, perpendicular X, type line|circle|other, \
                    circular [r=2.75], farthest +X, on <face name>. Combine with 'and'.
                    """),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.findGeometry(arguments)
    }
}

extension CADSession {
    func findGeometry(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        do throws(ToolError) {
            let arguments = try Arguments(raw, allowed: ["part", "instance", "body", "kind", "filter"])
            let kindName = try arguments.requiredString("kind")
            guard let kind = GeometryKind(rawValue: kindName) else {
                throw ToolError("'kind' is faces or edges, not '\(kindName)'.")
            }
            let filter = try arguments.string("filter")
            if let instanceName = try arguments.string("instance") {
                guard !arguments.has("part") else { throw ToolError("Give 'part' or 'instance', not both.") }
                _ = try document.instanceIndex(named: instanceName)
                guard let result = await currentResult() else {
                    throw ToolError("The model could not be rebuilt; call get_listing to see the statuses.")
                }
                let instance = try builtInstance(named: instanceName, in: result)
                let body = try instance.body(named: try arguments.string("body"))
                let partName = document.part(id: instance.part)?.name ?? "missing part"
                return try Self.listing(
                    kind, of: body, header: "\(instance.name) (\(partName)/\(body.name))", filter: filter,
                    parameters: result.parameters)
            }
            let partID = document.parts[try document.partIndex(named: try arguments.string("part"))].id
            let bodyName = try arguments.requiredString("body")
            guard let result = await currentResult(), let part = result.parts.first(where: { $0.id == partID }) else {
                throw ToolError("The model could not be rebuilt; call get_listing to see the statuses.")
            }
            guard let body = part.bodies.first(where: { $0.name == bodyName }) else {
                let bodies = part.bodies.map(\.name).joined(separator: ", ")
                throw ToolError(
                    "Part \(part.name) has no body named '\(bodyName)'. Bodies: \(bodies.isEmpty ? "none" : bodies).")
            }
            return try Self.listing(
                kind, of: body, header: "\(bodyName) (\(part.name))", filter: filter, parameters: result.parameters)
        } catch {
            return .failure(error.description)
        }
    }

    private static func listing(
        _ kind: GeometryKind, of body: BodyResult, header: String, filter: String?, parameters: ParameterTable
    ) throws(ToolError) -> ToolExecutionResult {
        guard let topology = body.topology else {
            throw ToolError("\(body.name) has no faces to list: \(body.error ?? "the kernel did not describe it").")
        }
        let names = TopologyNames(topology)
        let matches: [Int]
        do {
            matches = try GeometryResolver.select(
                kind, filter: filter, in: topology, names: names, parameters: parameters)
        } catch {
            throw ToolError(error.description)
        }
        return .success(
            GeometryListing.render(kind, matches, topology: topology, names: names, header: header, filter: filter))
    }
}

enum GeometryListing {
    static func render(
        _ kind: GeometryKind, _ matches: [Int], topology: BodyTopology, names: TopologyNames, header: String,
        filter: String?
    ) -> String {
        let total = kind == .faces ? topology.faces.count : topology.edges.count
        var lines: [String] = []
        if let filter {
            lines.append("\(header): \(matches.count) of \(total) \(kind.rawValue) match \"\(filter)\"")
        } else {
            lines.append("\(header): \(total) \(kind.rawValue)")
        }
        for index in matches {
            lines.append("  " + (kind == .faces ? face(index, topology, names) : edge(index, topology, names)))
        }
        return lines.joined(separator: "\n")
    }

    static func face(_ index: Int, _ topology: BodyTopology, _ names: TopologyNames) -> String {
        let face = topology.faces[index]
        var parts = [names.faces[index], face.surface.rawValue, "centre \(Format.point(face.centroid))"]
        if let normal = face.normal { parts.append("normal \(Format.point(normal))") }
        if let axis = face.axis {
            parts.append("axis \(Format.point(axis))" + (face.axisOrigin.map { " through \(Format.point($0))" } ?? ""))
        } else if face.surface == .sphere, let origin = face.axisOrigin {
            parts.append("centred on \(Format.point(origin))")
        }
        if let radius = face.radius { parts.append("r=\(Format.number(radius))") }
        parts.append("area \(Format.number(face.area))")
        if face.names.count > 1 { parts.append("also \(face.names.dropFirst().joined(separator: ", "))") }
        return parts.joined(separator: "  ")
    }

    static func edge(_ index: Int, _ topology: BodyTopology, _ names: TopologyNames) -> String {
        let edge = topology.edges[index]
        var parts = [names.edges[index], edge.curve.rawValue]
        switch edge.curve {
        case .circle:
            if let radius = edge.radius { parts.append("r=\(Format.number(radius))") }
            if let center = edge.center { parts.append("centre \(Format.point(center))") }
            if let axis = edge.axis { parts.append("axis \(Format.point(axis))") }
        case .line:
            parts.append("from \(Format.point(edge.start)) to \(Format.point(edge.end))")
        case .other:
            parts.append("midpoint \(Format.point(edge.midpoint))")
        }
        parts.append("length \(Format.number(edge.length))")
        return parts.joined(separator: "  ")
    }
}
