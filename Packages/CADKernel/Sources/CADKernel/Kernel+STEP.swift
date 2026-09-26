import Foundation
import OCCTSwift
import simd

/// A part written once to a STEP file: its bodies at the part's own coordinates.
public struct STEPProduct: @unchecked Sendable {
    public var name: String
    public var bodies: [(name: String, solid: Solid)]
    /// Red, green and blue in 0…1.
    public var color: SIMD3<Double>

    public init(name: String, bodies: [(name: String, solid: Solid)], color: SIMD3<Double>) {
        self.name = name
        self.bodies = bodies
        self.color = color
    }
}

/// A product placed in the assembly by a rotation followed by a translation (mm).
public struct STEPOccurrence: Sendable {
    public var name: String
    public var product: Int
    public var rotation: simd_double3x3
    public var translation: SIMD3<Double>

    public init(name: String, product: Int, rotation: simd_double3x3, translation: SIMD3<Double>) {
        self.name = name
        self.product = product
        self.rotation = rotation
        self.translation = translation
    }
}

/// What a STEP file holds, read back through Open CASCADE.
public struct STEPContents: @unchecked Sendable {
    /// Every solid, placed in the file's coordinates.
    public let solids: [Solid]
    /// The name of every node in the product tree, depth first.
    public let names: [String]
    /// The colour of every coloured node.
    public let colors: [SIMD3<Double>]
}

extension Kernel {
    /// Writes the products with their names and colours, in millimetres. Without occurrences each product is a free
    /// shape; otherwise one assembly named `name` places them, and each product's geometry is written once.
    public static func writeSTEP(
        products: [STEPProduct], occurrences: [STEPOccurrence], name: String, to url: URL
    ) throws {
        try OCCTSerial.withLock {
            guard let document = Document.create() else { throw KernelError.operationFailed("write the STEP file") }
            var productLabels: [Int64] = []
            for product in products {
                try productLabels.append(add(product, to: document))
            }
            if !occurrences.isEmpty {
                let root = document.newShapeLabel()
                try setName(root, name, in: document)
                for occurrence in occurrences {
                    guard productLabels.indices.contains(occurrence.product) else {
                        throw KernelError.operationFailed("place \(occurrence.name): it has no product")
                    }
                    let component = document.addComponent(
                        assemblyLabelId: root, shapeLabelId: productLabels[occurrence.product],
                        matrix: rowMajor(occurrence.rotation, occurrence.translation)
                    )
                    try setName(component, occurrence.name, in: document)
                }
            }
            document.updateAssemblies()
            do {
                try Exporter.writeSTEPAssembly(document, to: url)
            } catch {
                throw KernelError.operationFailed("write the STEP file \(url.lastPathComponent)")
            }
        }
    }

    public static func readSTEP(from url: URL) throws -> STEPContents {
        try OCCTSerial.withLock {
            let document: Document
            let shape: Shape
            do {
                document = try Document.loadSTEP(from: url)
                shape = try Shape.loadSTEP(from: url)
            } catch {
                throw KernelError.operationFailed("read the STEP file \(url.lastPathComponent)")
            }
            var names: [String] = []
            var colors: [SIMD3<Double>] = []
            func walk(_ node: AssemblyNode) {
                if let name = node.name, !name.isEmpty {
                    names.append(name)
                }
                if let color = node.color {
                    colors.append(SIMD3(color.red, color.green, color.blue))
                }
                node.children.forEach(walk)
            }
            document.rootNodes.forEach(walk)
            for shape in document.allShapes() {
                if let color = document.shapeColor(shape) {
                    colors.append(SIMD3(color.red, color.green, color.blue))
                }
            }
            return STEPContents(
                solids: shape.solids.map { Solid(shape: $0, feature: "STEP") }, names: names, colors: colors
            )
        }
    }

    private static func add(_ product: STEPProduct, to document: Document) throws -> Int64 {
        let color = OCCTSwift.Color(red: product.color.x, green: product.color.y, blue: product.color.z)
        guard product.bodies.count != 1 else {
            let label = document.addShape(product.bodies[0].solid.shape, makeAssembly: false)
            try setName(label, product.name, in: document)
            document.node(at: label)?.setColor(color)
            return label
        }
        let label = document.newShapeLabel()
        try setName(label, product.name, in: document)
        for body in product.bodies {
            let bodyLabel = document.addShape(body.solid.shape, makeAssembly: false)
            try setName(bodyLabel, body.name, in: document)
            document.node(at: bodyLabel)?.setColor(color)
            let component = document.addComponent(
                assemblyLabelId: label, shapeLabelId: bodyLabel,
                matrix: rowMajor(matrix_identity_double3x3, .zero)
            )
            try setName(component, body.name, in: document)
        }
        return label
    }

    private static func setName(_ label: Int64, _ name: String, in document: Document) throws {
        guard label >= 0, let node = document.node(at: label), node.setName(name) else {
            throw KernelError.operationFailed("write \(name) to the STEP file")
        }
    }

    /// The rotation re-orthonormalised, because Open CASCADE refuses a placement that is not exactly rigid.
    private static func rowMajor(_ rotation: simd_double3x3, _ translation: SIMD3<Double>) -> [Double] {
        let r = simd_double3x3(simd_normalize(simd_quatd(rotation)))
        return [
            r[0][0], r[1][0], r[2][0],
            r[0][1], r[1][1], r[2][1],
            r[0][2], r[1][2], r[2][2],
            translation.x, translation.y, translation.z,
        ]
    }
}
