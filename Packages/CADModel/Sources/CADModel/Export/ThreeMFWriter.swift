import Foundation
import simd

/// A 3MF package: one mesh object per product body, one components object per product with several bodies, one
/// build item per occurrence (or per product without occurrences), each product coloured by a base material. An
/// occurrence with its own colour places a copy of its product's meshes in that colour, because 3MF colours objects,
/// not items.
public enum ThreeMFWriter {
    static let modelPath = "3D/3dmodel.model"

    public static func data(_ scene: ExportScene<BodyMesh>) -> Data {
        var archive = ZipArchive()
        archive.add("[Content_Types].xml", Data(contentTypes.utf8))
        archive.add("_rels/.rels", Data(relationships.utf8))
        archive.add(modelPath, Data(model(scene).utf8))
        return archive.data()
    }

    private static let contentTypes = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
        </Types>
        """

    private static let relationships = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Target="/\(modelPath)" Id="rel0" \
        Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
        </Relationships>
        """

    static func model(_ scene: ExportScene<BodyMesh>) -> String {
        var materials = scene.products.map { (name: $0.name, color: hex($0.color)) }
        func material(_ color: SIMD3<Double>) -> Int {
            let code = hex(color)
            if let index = materials.firstIndex(where: { $0.color == code }) { return index }
            materials.append((code, code))
            return materials.count - 1
        }
        let occurrenceMaterials = scene.occurrences.map { $0.color.map(material) ?? $0.product }
        var objects = ""
        var nextID = 2
        var emitted: [[Int]: Int] = [:]
        func productObject(_ index: Int, material: Int) -> Int {
            if let id = emitted[[index, material]] { return id }
            let product = scene.products[index]
            var bodyObjects: [Int] = []
            for (name, mesh) in product.bodies {
                let objectName = product.bodies.count == 1 ? product.name : name
                objects += object(nextID, name: objectName, material: material, mesh: mesh)
                bodyObjects.append(nextID)
                nextID += 1
            }
            var id = bodyObjects[0]
            if bodyObjects.count > 1 {
                objects += "<object id=\"\(nextID)\" type=\"model\" name=\"\(escape(product.name))\"><components>\n"
                objects += bodyObjects.map { "<component objectid=\"\($0)\"/>\n" }.joined()
                objects += "</components></object>\n"
                id = nextID
                nextID += 1
            }
            emitted[[index, material]] = id
            return id
        }
        let productObjects = scene.products.indices.map { productObject($0, material: $0) }
        let items =
            scene.occurrences.isEmpty
            ? productObjects.map { "<item objectid=\"\($0)\"/>\n" }
            : zip(scene.occurrences, occurrenceMaterials).map { occurrence, material in
                let id = productObject(occurrence.product, material: material)
                return "<item objectid=\"\(id)\" transform=\"\(transform(occurrence.transform))\"/>\n"
            }
        var resources = "<basematerials id=\"1\">\n"
        for (name, color) in materials {
            resources += "<base name=\"\(escape(name))\" displaycolor=\"\(color)\"/>\n"
        }
        resources += "</basematerials>\n" + objects
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <model unit="millimeter" xml:lang="en-US" \
            xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
            <metadata name="Application">3D Modeller</metadata>
            <metadata name="Title">\(escape(scene.name))</metadata>
            <resources>
            \(resources)</resources>
            <build>
            \(items.joined())</build>
            </model>
            """
    }

    private static func object(_ id: Int, name: String, material: Int, mesh: BodyMesh) -> String {
        let (positions, triangles) = welded(mesh)
        var text = "<object id=\"\(id)\" type=\"model\" name=\"\(escape(name))\" pid=\"1\" pindex=\"\(material)\">"
        text += "<mesh><vertices>\n"
        for p in positions {
            text += "<vertex x=\"\(p.x)\" y=\"\(p.y)\" z=\"\(p.z)\"/>\n"
        }
        text += "</vertices><triangles>\n"
        for (a, b, c) in triangles {
            text += "<triangle v1=\"\(a)\" v2=\"\(b)\" v3=\"\(c)\"/>\n"
        }
        return text + "</triangles></mesh></object>\n"
    }

    /// The kernel meshes each face on its own, so the corners along shared edges are repeated; 3MF needs every
    /// edge shared by two triangles. The repeats are the same edge nodes, so exact positions merge them.
    static func welded(_ mesh: BodyMesh) -> (positions: [SIMD3<Float>], triangles: [(Int, Int, Int)]) {
        var index: [SIMD3<Float>: Int] = [:]
        var positions: [SIMD3<Float>] = []
        let remap = mesh.positions.map { position in
            if let known = index[position] { return known }
            index[position] = positions.count
            positions.append(position)
            return positions.count - 1
        }
        var triangles: [(Int, Int, Int)] = []
        for start in stride(from: 0, to: mesh.triangleCount * 3, by: 3) {
            let (a, b, c) = (
                remap[Int(mesh.indices[start])], remap[Int(mesh.indices[start + 1])],
                remap[Int(mesh.indices[start + 2])]
            )
            if a != b, b != c, a != c { triangles.append((a, b, c)) }
        }
        return (positions, triangles)
    }

    /// 3MF multiplies row vectors, so each rotation column comes first, then the translation.
    private static func transform(_ transform: RigidTransform) -> String {
        let r = transform.rotation
        let t = transform.translation
        return [r[0].x, r[0].y, r[0].z, r[1].x, r[1].y, r[1].z, r[2].x, r[2].y, r[2].z, t.x, t.y, t.z]
            .map { "\($0)" }.joined(separator: " ")
    }

    private static func hex(_ color: SIMD3<Double>) -> String {
        let channels = [color.x, color.y, color.z].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return "#" + channels.map { String(format: "%02X", $0) }.joined()
    }

    static func escape(_ text: String) -> String {
        let allowed = String(text.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        return allowed.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
