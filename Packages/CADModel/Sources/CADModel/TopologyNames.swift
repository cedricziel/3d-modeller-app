/// A unique display name for every face and edge of a body. A face goes by its primary name, with `[i]` when
/// several faces share it (a face split by a later feature), ordered by centroid x, then y, then z. An edge goes by
/// `edge(A, B)`, the sorted primary names of its faces, with `[i]` when several edges share them, ordered by midpoint.
public struct TopologyNames: Sendable, Equatable {
    public let faces: [String]
    public let edges: [String]

    public init(_ topology: BodyTopology) {
        faces = Self.disambiguate(
            topology.faces.map { $0.names.first ?? "face" }, centres: topology.faces.map(\.centroid))
        edges = Self.disambiguate(
            topology.edges.map { Self.edgeName(faces: $0.faces.map { topology.faces[$0].names.first ?? "face" }) },
            centres: topology.edges.map(\.midpoint))
    }

    public func names(_ kind: GeometryKind) -> [String] { kind == .faces ? faces : edges }

    static func edgeName(faces: [String]) -> String {
        "edge(\(faces.sorted().joined(separator: ", ")))"
    }

    static func disambiguate(_ bases: [String], centres: [SIMD3<Double>]) -> [String] {
        var names = bases
        for indices in Dictionary(grouping: bases.indices, by: { bases[$0] }).values where indices.count > 1 {
            for (piece, index) in ordered(indices, centres: centres).enumerated() {
                names[index] = "\(bases[index])[\(piece)]"
            }
        }
        return names
    }

    static func ordered(_ indices: [Int], centres: [SIMD3<Double>]) -> [Int] {
        func key(_ index: Int) -> [Double] {
            let c = centres[index]
            return [c.x, c.y, c.z].map { ($0 * 1e6).rounded() }
        }
        return indices.sorted { key($0).lexicographicallyPrecedes(key($1)) }
    }
}
