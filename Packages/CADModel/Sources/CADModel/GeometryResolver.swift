import Foundation

public enum GeometryResolver {
    static let listLimit = 25

    /// The faces or edges the references pick, sorted and without repeats. A name must match exactly one; a filter
    /// at least one. Otherwise the error lists the candidates.
    public static func resolve(
        _ references: [GeometryReference], kind: GeometryKind, in topology: BodyTopology,
        parameters: ParameterTable
    ) throws(ReferenceError) -> [Int] {
        let names = TopologyNames(topology)
        var selected = Set<Int>()
        for reference in references {
            switch reference {
            case .name(let text):
                selected.insert(try resolveName(text, kind: kind, in: topology, names: names))
            case .filter(let text):
                let matches = try select(kind, filter: text, in: topology, names: names, parameters: parameters)
                guard !matches.isEmpty else {
                    throw ReferenceError(
                        "No \(kind.singular) matches the filter '\(text)'. \(kind.rawValue.capitalized) of this body: "
                            + list(kind, Array(0..<topology.count(kind)), topology, names))
                }
                selected.formUnion(matches)
            }
        }
        return selected.sorted()
    }

    /// Every face or edge the filter keeps; all of them when there is no filter. Filters never pick seam edges
    /// (an edge with the same face on both sides), which no fillet or chamfer can take; a name still can.
    public static func select(
        _ kind: GeometryKind, filter: String?, in topology: BodyTopology, names: TopologyNames,
        parameters: ParameterTable
    ) throws(ReferenceError) -> [Int] {
        let all = Array(0..<topology.count(kind))
        guard let filter, !filter.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        let candidates = kind == .edges ? all.filter { topology.edges[$0].faces.count == 2 } : all
        return try GeometryFilter(parsing: filter, kind: kind).select(candidates, in: topology, names: names) {
            (expression) throws(ReferenceError) -> Double in
            do {
                return try parameters.evaluate(.expression(expression))
            } catch {
                throw ReferenceError("'\(expression)' in the filter '\(filter)': \(error)")
            }
        }
    }

    /// A name must match exactly one face or edge. Every face that carries the name counts, not only the one whose
    /// display name it is, so a face merged from two inputs makes the other input's name ambiguous.
    static func resolveName(
        _ text: String, kind: GeometryKind, in topology: BodyTopology, names: TopologyNames
    ) throws(ReferenceError) -> Int {
        let exact = names.names(kind).firstIndex(of: text)
        var matches: [Int]
        switch kind {
        case .faces:
            matches = faces(named: text, in: topology, names: names)
        case .edges:
            var body = Substring(text)
            var piece: Int?
            if body.hasSuffix("]"), let open = body.lastIndex(of: "["),
                let index = Int(body[open...].dropFirst().dropLast()),
                body[..<open].hasSuffix(")")
            {
                piece = index
                body = body[..<open]
            }
            guard body.hasPrefix("edge("), body.hasSuffix(")") else {
                if let exact { return exact }
                throw ReferenceError(
                    "'\(text)' is not an edge name; edges are named by their faces, like edge(Box1.front, Box1.top). "
                        + "Edges of this body: \(list(.edges, Array(topology.edges.indices), topology, names))")
            }
            let parts = splitTopLevel(body.dropFirst(5).dropLast())
            guard (1...2).contains(parts.count) else {
                throw ReferenceError("'\(text)' names \(parts.count) faces; an edge lies between one or two faces.")
            }
            if let piece {
                if let exact { return exact }
                let canonical = "\(TopologyNames.edgeName(faces: parts))[\(piece)]"
                if let index = names.edges.firstIndex(of: canonical) { return index }
            }
            var sets: [Set<Int>] = []
            for part in parts {
                let found = faces(named: part, in: topology, names: names)
                guard !found.isEmpty else {
                    throw ReferenceError(
                        "No face is named '\(part)' (in '\(text)'). Faces of this body: "
                            + list(.faces, Array(topology.faces.indices), topology, names))
                }
                sets.append(Set(found))
            }
            matches = topology.edges.indices.filter { index in
                let faces = topology.edges[index].faces
                if sets.count == 1 { return faces.count == 1 && sets[0].contains(faces[0]) }
                guard faces.count == 2 else { return false }
                return (sets[0].contains(faces[0]) && sets[1].contains(faces[1]))
                    || (sets[0].contains(faces[1]) && sets[1].contains(faces[0]))
            }
            if piece != nil { matches = [] }
        }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 {
            throw ReferenceError(
                "'\(text)' matches \(matches.count) \(kind.rawValue); name one of them: "
                    + list(kind, matches, topology, names))
        }
        throw ReferenceError(
            "No \(kind.singular) is named '\(text)'. \(kind.rawValue.capitalized) of this body: "
                + list(kind, Array(0..<topology.count(kind)), topology, names))
    }

    /// Faces that carry `text` among their names, or else the face whose display name it is (a piece such as
    /// `Box1.top[1]`).
    static func faces(named text: String, in topology: BodyTopology, names: TopologyNames) -> [Int] {
        let carriers = topology.faces.indices.filter { topology.faces[$0].names.contains(text) }
        if carriers.isEmpty, let exact = names.faces.firstIndex(of: text) { return [exact] }
        return carriers
    }

    private static func splitTopLevel(_ text: Substring) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            switch character {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            default: break
            }
            current.append(character)
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts.filter { !$0.isEmpty }
    }

    static func list(_ kind: GeometryKind, _ indices: [Int], _ topology: BodyTopology, _ names: TopologyNames)
        -> String
    {
        guard !indices.isEmpty else { return "none" }
        let shown = indices.prefix(listLimit).map { describe(kind, $0, topology, names) }
        let rest = indices.count > listLimit ? "; and \(indices.count - listLimit) more (call find_geometry)" : ""
        return shown.joined(separator: "; ") + rest
    }

    static func describe(_ kind: GeometryKind, _ index: Int, _ topology: BodyTopology, _ names: TopologyNames)
        -> String
    {
        switch kind {
        case .faces:
            let face = topology.faces[index]
            return "\(names.faces[index]) (\(face.surface.rawValue) at \(ReferenceFormat.point(face.centroid)))"
        case .edges:
            let edge = topology.edges[index]
            return "\(names.edges[index]) (\(edge.curve.rawValue) at \(ReferenceFormat.point(edge.midpoint)))"
        }
    }
}

enum ReferenceFormat {
    static func number(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == 0 { return "0" }
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int64(rounded)) }
        return String(rounded)
    }

    static func point(_ point: SIMD3<Double>) -> String {
        "(\(number(point.x)), \(number(point.y)), \(number(point.z)))"
    }
}
