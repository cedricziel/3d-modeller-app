import OCCTSwift

enum Naming {
    static func fallback(_ count: Int, feature: String, existing: Set<String> = []) -> [[String]] {
        var next = 0
        return (0..<count).map { _ in [freeName(feature, &next, existing)] }
    }

    static func freeName(_ feature: String, _ next: inout Int, _ existing: Set<String>) -> String {
        while existing.contains("\(feature).face[\(next)]") { next += 1 }
        defer { next += 1 }
        return "\(feature).face[\(next)]"
    }

    /// Names the faces of a freshly made primitive by the role each plays in its own frame.
    static func roles(of shape: Shape, feature: String, role: (Face) -> String) -> [[String]] {
        shape.subShapes(ofType: .face).map { face in
            [Face(face).map { "\(feature).\(role($0))" } ?? "\(feature).face"]
        }
    }

    static func boxRole(_ face: Face) -> String {
        let n = face.normal ?? .zero
        let magnitudes = [abs(n.x), abs(n.y), abs(n.z)]
        switch magnitudes.firstIndex(of: magnitudes.max()!)! {
        case 0: return n.x < 0 ? "left" : "right"
        case 1: return n.y < 0 ? "front" : "back"
        default: return n.z < 0 ? "bottom" : "top"
        }
    }

    static func axialRole(_ face: Face) -> String {
        guard face.surfaceType == .plane else { return "side" }
        return (face.normal?.z ?? 0) < 0 ? "bottom" : "top"
    }
}

extension Naming {
    struct Input {
        let shape: Shape
        let names: [[String]]
    }

    /// Names the faces of an operation's result from the inputs they came from, following OCCT's history: a face
    /// left alone or modified keeps its names; a face generated from a named face gets `generatedFromFace(name)`;
    /// a face generated from `edges[i]` gets `generatedFromEdge(i)`; every other face `<feature>.face[k]`.
    static func carry(
        _ inputs: [Input], into result: Shape, history: ShapeHistoryRef, feature: String,
        edges: [Shape] = [], generatedFromEdge: ((Int) -> String)? = nil,
        generatedFromFace: ((String) -> String)? = nil
    ) -> [[String]] {
        let faces = result.subShapes(ofType: .face)
        var names = [[String]](repeating: [], count: faces.count)
        func indices(of shapes: [Shape]) -> [Int] {
            shapes.compactMap { shape in faces.firstIndex { $0.isSame(as: shape) } }
        }
        var generated: [(index: Int, name: String)] = []
        for input in inputs {
            for (face, faceNames) in zip(input.shape.subShapes(ofType: .face), input.names) {
                let record = history.record(of: face)
                var targets = indices(of: record.modified)
                if let same = faces.firstIndex(where: { $0.isSame(as: face) }) { targets.append(same) }
                for index in targets {
                    for name in faceNames where !names[index].contains(name) { names[index].append(name) }
                }
                if let generatedFromFace, let primary = faceNames.first {
                    generated += indices(of: record.generated).map { ($0, generatedFromFace(primary)) }
                }
            }
        }
        if let generatedFromEdge {
            for (position, edge) in edges.enumerated() {
                generated += indices(of: history.record(of: edge).generated).map { ($0, generatedFromEdge(position)) }
            }
        }
        for (index, name) in generated where names[index].isEmpty { names[index] = [name] }
        return fillGaps(names, feature: feature)
    }

    /// Gives every unnamed face the next free `<feature>.face[k]`.
    static func fillGaps(_ names: [[String]], feature: String) -> [[String]] {
        let existing = Set(names.flatMap(\.self))
        var next = 0
        return names.map { $0.isEmpty ? [freeName(feature, &next, existing)] : $0 }
    }

    /// Names of each solid's faces, looked up in the solid it was taken from.
    static func names(of part: Shape, in whole: Shape, names: [[String]]) -> [[String]] {
        let faces = whole.subShapes(ofType: .face)
        return part.subShapes(ofType: .face).map { face in
            faces.firstIndex { $0.isSame(as: face) }.map { names[$0] } ?? []
        }
    }
}
