import Foundation
import Testing
import simd

@testable import CADModel

/// A 10 × 10 × 10 box `B` from the origin, plus a cylindrical hole wall `H.side` of radius 2 whose top circle meets
/// `B.top`.
private func drilledBox() -> BodyTopology {
    var topology = BodyTopology.box("B", size: SIMD3(10, 10, 10))
    topology.faces.append(
        FaceDescriptor(
            names: ["H.side"], surface: .cylinder, centroid: SIMD3(5, 5, 5), area: 1, axisOrigin: SIMD3(5, 5, 0),
            axis: SIMD3(0, 0, 1), radius: 2))
    let top = topology.faces.firstIndex { $0.names == ["B.top"] }!
    topology.edges.append(
        EdgeDescriptor(
            faces: [top, 6], curve: .circle, length: 4 * .pi, start: SIMD3(7, 5, 10), end: SIMD3(7, 5, 10),
            midpoint: SIMD3(3, 5, 10), center: SIMD3(5, 5, 10), axis: SIMD3(0, 0, 1), radius: 2))
    return topology
}

/// The box with its top split in two by a slot along Y: both pieces are named `B.top`.
private func slottedBox() -> BodyTopology {
    var topology = BodyTopology.box("B", size: SIMD3(10, 10, 10))
    let top = topology.faces.firstIndex { $0.names == ["B.top"] }!
    topology.faces[top].centroid = SIMD3(8, 5, 10)
    topology.faces.append(
        FaceDescriptor(names: ["B.top"], surface: .plane, centroid: SIMD3(2, 5, 10), area: 1, normal: SIMD3(0, 0, 1)))
    return topology
}

private func resolve(
    _ texts: [String], _ kind: GeometryKind, in topology: BodyTopology, parameters: [Parameter] = []
) throws(ReferenceError) -> [String] {
    let names = TopologyNames(topology)
    return try GeometryResolver.resolve(
        texts.map(GeometryReference.init(parsing:)), kind: kind, in: topology, parameters: ParameterTable(parameters)
    ).map { names.names(kind)[$0] }
}

private func error(_ body: () throws -> Void) -> String {
    do {
        try body()
        return ""
    } catch {
        return String(describing: error)
    }
}

@Suite("Topology names")
struct TopologyNamesTests {
    @Test("Faces go by their primary name, edges by their sorted faces")
    func plainNames() {
        let names = TopologyNames(drilledBox())

        #expect(names.faces == ["B.left", "B.right", "B.front", "B.back", "B.bottom", "B.top", "H.side"])
        #expect(names.edges.contains("edge(B.front, B.top)"))
        #expect(names.edges.last == "edge(B.top, H.side)")
        #expect(Set(names.edges).count == names.edges.count)
    }

    @Test("Pieces of a split face are numbered by centroid")
    func pieces() {
        let names = TopologyNames(slottedBox())

        #expect(names.faces[5] == "B.top[1]")
        #expect(names.faces[6] == "B.top[0]")
    }
}

@Suite("Geometry references")
struct GeometryReferenceTests {
    @Test("A text starting with a filter keyword is a filter, anything else a name")
    func parsing() {
        #expect(GeometryReference(parsing: " parallel Z ") == .filter("parallel Z"))
        #expect(GeometryReference(parsing: "Edges on B.top") == .filter("Edges on B.top"))
        #expect(GeometryReference(parsing: "edge(B.front, B.top)") == .name("edge(B.front, B.top)"))
        #expect(GeometryReference(parsing: "normal.top") == .name("normal.top"))
    }

    @Test("References encode as a name or a filter object")
    func coding() throws {
        let references: [GeometryReference] = [.name("B.top"), .filter("parallel Z")]
        let json = try JSONEncoder().encode(references)

        #expect(String(decoding: json, as: UTF8.self) == #"[{"name":"B.top"},{"filter":"parallel Z"}]"#)
        #expect(try JSONDecoder().decode([GeometryReference].self, from: json) == references)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GeometryReference.self, from: Data(#"{"name":"a","filter":"b"}"#.utf8))
        }
    }

    @Test("Renaming a feature rewrites its prefix only where it names that feature")
    func renaming() {
        #expect(
            GeometryReference.name("edge(Box1.top, Box1.front)").renamingFeature("Box1", to: "Plate")
                == .name("edge(Plate.top, Plate.front)"))
        #expect(GeometryReference.filter("on Box1.top").renamingFeature("Box1", to: "Plate") == .filter("on Plate.top"))
        #expect(GeometryReference.name("Box10.top").renamingFeature("Box1", to: "Plate") == .name("Box10.top"))
        #expect(GeometryReference.name("MyBox1.top").renamingFeature("Box1", to: "Plate") == .name("MyBox1.top"))
    }
}

@Suite("Reference resolution")
struct GeometryResolverTests {
    @Test("Names pick one face or edge, in either face order")
    func names() throws {
        #expect(try resolve(["B.top", "H.side"], .faces, in: drilledBox()) == ["B.top", "H.side"])
        #expect(try resolve(["edge(B.top, B.front)"], .edges, in: drilledBox()) == ["edge(B.front, B.top)"])
        #expect(try resolve(["edge(H.side, B.top)"], .edges, in: drilledBox()) == ["edge(B.top, H.side)"])
    }

    @Test("A name that matches nothing fails and lists the candidates")
    func unknownName() {
        let message = error { _ = try resolve(["B.lid"], .faces, in: drilledBox()) }

        #expect(message.hasPrefix("No face is named 'B.lid'. Faces of this body: B.left (plane at (0, 5, 5));"))
        #expect(message.contains("H.side (cylinder at (5, 5, 5))"))
        #expect(
            error { _ = try resolve(["edge(B.top, B.bottom)"], .edges, in: drilledBox()) }.contains(
                "edge(B.front, B.top)"))
        #expect(
            error { _ = try resolve(["edge(B.top, Q.side)"], .edges, in: drilledBox()).count }.hasPrefix(
                "No face is named 'Q.side'"))
        #expect(error { _ = try resolve(["B.top"], .edges, in: drilledBox()) }.contains("is not an edge name"))
    }

    @Test("A name shared by the pieces of a split face is ambiguous; a piece index picks one")
    func splitFaceAmbiguous() throws {
        let message = error { _ = try resolve(["B.top"], .faces, in: slottedBox()) }

        #expect(
            message
                == "'B.top' matches 2 faces; name one of them: B.top[1] (plane at (8, 5, 10)); B.top[0] (plane at (2, 5, 10))"
        )
        #expect(try resolve(["B.top[0]"], .faces, in: slottedBox()) == ["B.top[0]"])
    }

    @Test("Edge filters select lines by direction, circles by radius, and combine left to right")
    func edgeFilters() throws {
        let topology = drilledBox()

        #expect(try resolve(["parallel Z"], .edges, in: topology).count == 4)
        #expect(
            try resolve(["edges parallel Z and farthest +X"], .edges, in: topology).sorted() == [
                "edge(B.back, B.right)", "edge(B.front, B.right)",
            ])
        #expect(
            try resolve(["perpendicular Z and farthest -Y"], .edges, in: topology).sorted() == [
                "edge(B.bottom, B.front)", "edge(B.front, B.top)",
            ])
        #expect(try resolve(["circular r=2"], .edges, in: topology) == ["edge(B.top, H.side)"])
        #expect(
            try resolve(["circular r = d / 2"], .edges, in: topology, parameters: [Parameter(name: "d", expression: 4)])
                == ["edge(B.top, H.side)"])
        #expect(try resolve(["type circle"], .edges, in: topology).count == 1)
        #expect(try resolve(["on B.top and type line"], .edges, in: topology).count == 4)
        #expect(try resolve(["parallel Z", "edge(B.front, B.top)"], .edges, in: topology).count == 5)
    }

    @Test("Face filters select by normal, type and radius")
    func faceFilters() throws {
        let topology = drilledBox()

        #expect(try resolve(["normal +Z"], .faces, in: topology) == ["B.top"])
        #expect(try resolve(["faces normal Z"], .faces, in: topology) == ["B.bottom", "B.top"])
        #expect(try resolve(["parallel Z and farthest -X"], .faces, in: topology) == ["B.left"])
        #expect(try resolve(["type cylinder"], .faces, in: topology) == ["H.side"])
        #expect(try resolve(["circular r=2.0005"], .faces, in: topology) == ["H.side"])
    }

    @Test("Filters that match nothing, or cannot be read, fail with the accepted forms")
    func filterErrors() {
        let topology = drilledBox()

        #expect(
            error { _ = try resolve(["circular r=3"], .edges, in: topology) }.hasPrefix(
                "No edge matches the filter 'circular r=3'. Edges of this body: "))
        #expect(
            error { _ = try resolve(["normal +Z"], .edges, in: topology) }.hasPrefix(
                "'normal +Z' is not an edge filter. Edge filters: parallel Z"))
        #expect(error { _ = try resolve(["farthest +Q"], .faces, in: topology) }.contains("is not a face filter"))
        #expect(
            error { _ = try resolve(["edges parallel Z"], .faces, in: topology) }
                == "'edges parallel Z' selects edges, but faces are needed here.")
        #expect(
            error { _ = try resolve(["parallel Z and"], .edges, in: topology) }.contains("is not a complete filter"))
        #expect(
            error { _ = try resolve(["circular r=nope"], .edges, in: topology) }.contains("unknown parameter 'nope'"))
        #expect(error { _ = try resolve(["on B.lid"], .edges, in: topology) }.hasPrefix("No face is named 'B.lid'."))
    }
}
