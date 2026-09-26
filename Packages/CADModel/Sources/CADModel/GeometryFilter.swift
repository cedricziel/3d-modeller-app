import simd

/// A CadQuery-style selection: `[edges|faces] clause (and clause)*`, applied left to right.
public struct GeometryFilter: Sendable, Equatable {
    enum Clause: Sendable, Equatable {
        case parallel(SIMD3<Double>)
        case perpendicular(SIMD3<Double>)
        case normal(SIMD3<Double>, signed: Bool)
        case surface(SurfaceKind)
        case curve(CurveKind)
        case circular(radius: String?)
        case farthest(SIMD3<Double>)
        case on(String)
    }

    static let angularTolerance = 1e-6
    static let lengthTolerance = 1e-3

    let kind: GeometryKind
    let clauses: [Clause]

    static func usage(_ kind: GeometryKind) -> String {
        switch kind {
        case .faces:
            "Face filters: normal +Z (planar faces facing +Z; Z for either way), parallel Z (planar faces whose "
                + "plane contains Z, such as side walls), perpendicular Z (same as normal Z), "
                + "type plane|cylinder|cone|sphere|torus|other, circular [r=2.75], farthest +X; combine with 'and'."
        case .edges:
            "Edge filters: parallel Z (straight edges along Z), perpendicular Z, type line|circle|other, "
                + "circular [r=2.75], farthest +X, on <face name>; combine with 'and'. Filters skip seam edges."
        }
    }

    public init(parsing text: String, kind: GeometryKind) throws(ReferenceError) {
        self.kind = kind
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if let first = words.first?.lowercased(), let named = GeometryKind(rawValue: first) {
            guard named == kind else {
                throw ReferenceError("'\(text)' selects \(named.rawValue), but \(kind.rawValue) are needed here.")
            }
            words.removeFirst()
        }
        var groups: [[String]] = [[]]
        for word in words {
            if word.lowercased() == "and" { groups.append([]) } else { groups[groups.count - 1].append(word) }
        }
        guard groups.allSatisfy({ !$0.isEmpty }) else {
            throw ReferenceError("'\(text)' is not a complete filter. \(Self.usage(kind))")
        }
        var clauses: [Clause] = []
        for group in groups {
            clauses.append(try Self.clause(group, kind: kind))
        }
        self.clauses = clauses
    }

    private static func clause(_ words: [String], kind: GeometryKind) throws(ReferenceError) -> Clause {
        let keyword = words[0].lowercased()
        let operand = words.dropFirst().joined(separator: " ")
        func bad() -> ReferenceError {
            ReferenceError(
                "'\(words.joined(separator: " "))' is not \(kind == .faces ? "a face" : "an edge") filter. \(usage(kind))"
            )
        }
        switch keyword {
        case "parallel":
            guard let axis = axis(operand, signed: false) else { throw bad() }
            return .parallel(axis.direction)
        case "perpendicular":
            guard let axis = axis(operand, signed: false) else { throw bad() }
            return .perpendicular(axis.direction)
        case "normal" where kind == .faces:
            guard let axis = axis(operand, signed: true) else { throw bad() }
            return .normal(axis.direction, signed: axis.signed)
        case "type":
            if kind == .faces, let surface = SurfaceKind(rawValue: operand.lowercased()) { return .surface(surface) }
            if kind == .edges, let curve = CurveKind(rawValue: operand.lowercased()) { return .curve(curve) }
            throw bad()
        case "circular":
            guard !operand.isEmpty else { return .circular(radius: nil) }
            let compact = operand.replacingOccurrences(of: " ", with: "")
            guard compact.hasPrefix("r="), compact.count > 2 else { throw bad() }
            let expression = operand.drop { $0 != "=" }.dropFirst().trimmingCharacters(in: .whitespaces)
            return .circular(radius: expression)
        case "farthest":
            guard let axis = axis(operand, signed: true) else { throw bad() }
            return .farthest(axis.direction)
        case "on" where kind == .edges:
            guard !operand.isEmpty else { throw bad() }
            return .on(operand)
        default:
            throw bad()
        }
    }

    private static func axis(_ text: String, signed: Bool) -> (direction: SIMD3<Double>, signed: Bool)? {
        var letters = Substring(text.uppercased())
        var sign = 1.0
        var hasSign = false
        if let first = letters.first, first == "+" || first == "-" {
            guard signed else { return nil }
            sign = first == "-" ? -1 : 1
            hasSign = true
            letters = letters.dropFirst()
        }
        let direction: SIMD3<Double>
        switch letters {
        case "X": direction = SIMD3(1, 0, 0)
        case "Y": direction = SIMD3(0, 1, 0)
        case "Z": direction = SIMD3(0, 0, 1)
        default: return nil
        }
        return (direction * sign, hasSign)
    }

    /// The indices among `candidates` the filter keeps.
    func select(
        _ candidates: [Int], in topology: BodyTopology, names: TopologyNames,
        evaluate: (String) throws(ReferenceError) -> Double
    ) throws(ReferenceError) -> [Int] {
        var selected = candidates
        for clause in clauses {
            switch clause {
            case .farthest(let direction):
                let reach = selected.map { simd_dot(topology.centre(kind, $0), direction) }
                guard let most = reach.max() else { continue }
                selected = zip(selected, reach).filter { $0.1 >= most - Self.lengthTolerance }.map(\.0)
            case .on(let faceName):
                let faces = Set(GeometryResolver.faces(named: faceName, in: topology, names: names))
                guard !faces.isEmpty else {
                    throw ReferenceError(
                        "No face is named '\(faceName)'. Faces: \(GeometryResolver.list(.faces, Array(topology.faces.indices), topology, names))"
                    )
                }
                selected = selected.filter { !faces.isDisjoint(with: topology.edges[$0].faces) }
            case .circular(let expression?):
                let wanted = try evaluate(expression)
                selected = selected.filter { index in
                    guard matches(.circular(radius: nil), index, topology), let actual = radius(of: index, topology)
                    else { return false }
                    return abs(actual - wanted) <= Self.lengthTolerance
                }
            default:
                selected = selected.filter { matches(clause, $0, topology) }
            }
        }
        return selected
    }

    private func radius(of index: Int, _ topology: BodyTopology) -> Double? {
        kind == .faces ? topology.faces[index].radius : topology.edges[index].radius
    }

    private func matches(_ clause: Clause, _ index: Int, _ topology: BodyTopology) -> Bool {
        let tolerance = Self.angularTolerance
        switch kind {
        case .faces:
            let face = topology.faces[index]
            switch clause {
            case .parallel(let axis):
                guard let normal = face.normal else { return false }
                return abs(simd_dot(normal, axis)) < tolerance
            case .perpendicular(let axis):
                guard let normal = face.normal else { return false }
                return abs(simd_dot(normal, axis)) > 1 - tolerance
            case .normal(let direction, let signed):
                guard let normal = face.normal else { return false }
                let dot = simd_dot(normal, direction)
                return (signed ? dot : abs(dot)) > 1 - tolerance
            case .surface(let surface): return face.surface == surface
            case .circular: return face.surface == .cylinder
            default: return false
            }
        case .edges:
            let edge = topology.edges[index]
            switch clause {
            case .parallel(let axis):
                guard let direction = edge.direction else { return false }
                return abs(simd_dot(direction, axis)) > 1 - tolerance
            case .perpendicular(let axis):
                guard let direction = edge.direction else { return false }
                return abs(simd_dot(direction, axis)) < tolerance
            case .curve(let curve): return edge.curve == curve
            case .circular: return edge.curve == .circle
            default: return false
            }
        }
    }
}
