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
