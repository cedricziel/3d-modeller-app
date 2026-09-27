import Foundation
import simd

public struct ThreeMFContents: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public let object: Int
        public let triangleCount: Int
        /// The item's vertices placed by its transform and its components'.
        public let bounds: Bounds
        /// Edges of its meshes not shared by exactly two triangles; 0 for a closed, manifold mesh.
        public let openEdgeCount: Int
        /// The display colour of each mesh it places, in order.
        public let colors: [String]
    }

    public let unit: String?
    public let objectNames: [String]
    public let colors: [String]
    public let items: [Item]

    public var triangleCount: Int { items.reduce(0) { $0 + $1.triangleCount } }
}

/// Reads back a 3MF package that `ThreeMFWriter` wrote, for checking exports.
public enum ThreeMFReader {
    public static func read(_ data: Data) throws(ExportError) -> ThreeMFContents {
        guard let model = try ZipArchive.entries(of: data)[ThreeMFWriter.modelPath] else {
            throw ExportError("The package has no \(ThreeMFWriter.modelPath)")
        }
        let parser = XMLParser(data: model)
        let collector = ModelCollector()
        parser.delegate = collector
        guard parser.parse() else {
            throw ExportError(
                "The 3MF model is not valid XML: \(parser.parserError.map(String.init(describing:)) ?? "")")
        }
        var items: [ThreeMFContents.Item] = []
        for (object, transform) in collector.items {
            var points: [SIMD3<Double>] = []
            var openEdges = 0
            var colors: [String] = []
            let triangles = try collector.place(
                object, transform, into: &points, openEdges: &openEdges, colors: &colors, depth: 0)
            guard let first = points.first else { throw ExportError("Build item \(object) has no vertices") }
            let bounds = points.reduce(Bounds(min: first, max: first)) {
                Bounds(min: simd_min($0.min, $1), max: simd_max($0.max, $1))
            }
            items.append(
                ThreeMFContents.Item(
                    object: object, triangleCount: triangles, bounds: bounds, openEdgeCount: openEdges,
                    colors: colors))
        }
        return ThreeMFContents(
            unit: collector.unit, objectNames: collector.objects.values.map(\.name).sorted(),
            colors: collector.colors, items: items)
    }
}

private final class ModelCollector: NSObject, XMLParserDelegate {
    struct Object {
        var name = ""
        var material: Int?
        var vertices: [SIMD3<Double>] = []
        var triangles: [[Int]] = []
        var components: [(Int, RigidTransform)] = []
    }

    var unit: String?
    var colors: [String] = []
    var objects: [Int: Object] = [:]
    var items: [(Int, RigidTransform)] = []
    private var current: Int?

    func parser(
        _ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        func number(_ key: String) -> Double { Double(attributes[key] ?? "") ?? .nan }
        switch element {
        case "model": unit = attributes["unit"]
        case "base": colors.append(attributes["displaycolor"] ?? "")
        case "object":
            current = Int(attributes["id"] ?? "")
            if let current {
                objects[current] = Object(name: attributes["name"] ?? "", material: Int(attributes["pindex"] ?? ""))
            }
        case "vertex":
            if let current { objects[current]?.vertices.append(SIMD3(number("x"), number("y"), number("z"))) }
        case "triangle":
            if let current {
                objects[current]?.triangles.append(["v1", "v2", "v3"].map { Int(attributes[$0] ?? "") ?? -1 })
            }
        case "component":
            if let current, let id = Int(attributes["objectid"] ?? "") {
                objects[current]?.components.append((id, Self.transform(attributes["transform"])))
            }
        case "item":
            if let id = Int(attributes["objectid"] ?? "") {
                items.append((id, Self.transform(attributes["transform"])))
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "object" { current = nil }
    }

    func place(
        _ id: Int, _ transform: RigidTransform, into points: inout [SIMD3<Double>], openEdges: inout Int,
        colors: inout [String], depth: Int
    ) throws(ExportError) -> Int {
        guard depth < 16, let object = objects[id] else {
            throw ExportError("Object \(id) is missing or nested too deep")
        }
        points += object.vertices.map(transform.point)
        if let material = object.material, !object.triangles.isEmpty {
            colors.append(self.colors.indices.contains(material) ? self.colors[material] : "")
        }
        var edgeUses: [[Int]: Int] = [:]
        for triangle in object.triangles {
            for (a, b) in [(triangle[0], triangle[1]), (triangle[1], triangle[2]), (triangle[2], triangle[0])] {
                edgeUses[[min(a, b), max(a, b)], default: 0] += 1
            }
        }
        openEdges += edgeUses.values.count { $0 != 2 }
        var triangles = object.triangles.count
        for (child, local) in object.components {
            triangles += try place(
                child, transform.composed(with: local), into: &points, openEdges: &openEdges, colors: &colors,
                depth: depth + 1)
        }
        return triangles
    }

    private static func transform(_ text: String?) -> RigidTransform {
        let values = (text ?? "").split(separator: " ").compactMap { Double($0) }
        guard values.count == 12 else { return .identity }
        return RigidTransform(
            rotation: simd_double3x3(
                SIMD3(values[0], values[1], values[2]), SIMD3(values[3], values[4], values[5]),
                SIMD3(values[6], values[7], values[8])),
            translation: SIMD3(values[9], values[10], values[11]))
    }
}
