import CADModel
import SwiftUIAssistant

/// One side of a measurement: a point, a body, or one face or edge of a body.
struct MeasureOperand: Sendable {
    enum Element: Sendable {
        case point(SIMD3<Double>)
        case body(BodyKey, BodyResult)
        case face(BodyKey, Int, FaceDescriptor)
        case edge(BodyKey, Int, EdgeDescriptor)
    }

    let element: Element
    let label: String

    var target: MeasureTarget {
        switch element {
        case .point(let point): .point(point)
        case .body(let key, _): .body(key)
        case .face(let key, let index, _): .face(key, index)
        case .edge(let key, let index, _): .edge(key, index)
        }
    }

    static let usage = """
        an object such as {"body": "Body1"}, {"body": "Body1", "face": "Plate.top"}, \
        {"body": "Body1", "edge": "edge(Plate.front, Plate.top)"} or {"point": [0, 0, 10]}
        """
}

extension CADSession {
    func measureOperand(_ value: JSONValue, _ name: String, in result: RebuildResult) throws(ToolError)
        -> MeasureOperand
    {
        guard let object = value.objectValue else { throw ToolError("'\(name)' must be \(MeasureOperand.usage).") }
        let arguments: Arguments
        do {
            arguments = try Arguments(object, allowed: ["part", "body", "face", "edge", "point"])
        } catch {
            throw ToolError("'\(name)': \(error.description)")
        }
        if arguments.has("point") {
            guard arguments.keys == ["point"] else {
                throw ToolError("'\(name)' is a point, which stands alone; drop 'part', 'body', 'face' and 'edge'.")
            }
            let point = try self.point(object["point"] ?? .null, name, result.parameters)
            return MeasureOperand(element: .point(point), label: "point \(Format.point(point))")
        }
        guard let bodyName = try arguments.string("body") else {
            throw ToolError("'\(name)' needs a 'body' or a 'point': \(MeasureOperand.usage).")
        }
        let partIndex = try document.partIndex(named: try arguments.string("part"))
        let partID = document.parts[partIndex].id
        guard let part = result.parts.first(where: { $0.id == partID }) else {
            throw ToolError("Part \(document.parts[partIndex].name) has no rebuilt bodies yet.")
        }
        guard result.parts.count(where: { $0.name == part.name }) == 1 else {
            throw ToolError("Several parts are named \(part.name); rename one before measuring.")
        }
        guard let body = part.bodies.first(where: { $0.name == bodyName }) else {
            let bodies = part.bodies.map(\.name).joined(separator: ", ")
            throw ToolError(
                "Part \(part.name) has no body named '\(bodyName)'. Bodies: \(bodies.isEmpty ? "none" : bodies).")
        }
        let key = BodyKey(part: part.name, body: bodyName)
        let face = try arguments.string("face")
        let edge = try arguments.string("edge")
        switch (face, edge) {
        case (nil, nil):
            return MeasureOperand(element: .body(key, body), label: key.description)
        case (let face?, nil):
            let (index, topology, label) = try element(face, .faces, of: body, key, result.parameters, name)
            return MeasureOperand(element: .face(key, index, topology.faces[index]), label: label)
        case (nil, let edge?):
            let (index, topology, label) = try element(edge, .edges, of: body, key, result.parameters, name)
            return MeasureOperand(element: .edge(key, index, topology.edges[index]), label: label)
        case (_?, _?):
            throw ToolError("'\(name)' names a face and an edge; measure one of them.")
        }
    }

    private func element(
        _ reference: String, _ kind: GeometryKind, of body: BodyResult, _ key: BodyKey, _ parameters: ParameterTable,
        _ name: String
    ) throws(ToolError) -> (Int, BodyTopology, String) {
        guard let topology = body.topology else {
            throw ToolError("\(key) has no faces to measure: \(body.error ?? "the kernel did not describe it").")
        }
        let matches: [Int]
        do {
            matches = try GeometryResolver.resolve(
                [GeometryReference(parsing: reference)], kind: kind, in: topology, parameters: parameters)
        } catch {
            throw ToolError("'\(name)': \(error.description)")
        }
        let names = TopologyNames(topology).names(kind)
        guard matches.count == 1 else {
            let shown = matches.prefix(10).map { names[$0] }.joined(separator: ", ")
            let more = matches.count > 10 ? ", … and \(matches.count - 10) more" : ""
            throw ToolError(
                "'\(name)': '\(reference)' matches \(matches.count) \(kind.rawValue) of \(key): \(shown)\(more). "
                    + "Measure one of them.")
        }
        return (matches[0], topology, "\(names[matches[0]]) of \(key)")
    }

    private func point(_ value: JSONValue, _ name: String, _ parameters: ParameterTable) throws(ToolError)
        -> SIMD3<Double>
    {
        let components: [JSONValue]
        if let array = value.arrayValue, array.count == 3 {
            components = array
        } else if let object = value.objectValue, Set(object.keys).isSubset(of: ["x", "y", "z"]) {
            components = ["x", "y", "z"].map { object[$0] ?? .integer(0) }
        } else {
            throw ToolError("'\(name).point' must be [x, y, z] in mm.")
        }
        var values: [Double] = []
        for (axis, component) in zip(["x", "y", "z"], components) {
            let scalar = try Arguments.scalar(component, "\(name).point.\(axis)")
            do {
                values.append(try parameters.evaluate(scalar))
            } catch {
                throw ToolError("'\(name).point.\(axis)': \(error)")
            }
        }
        return SIMD3(values[0], values[1], values[2])
    }
}
