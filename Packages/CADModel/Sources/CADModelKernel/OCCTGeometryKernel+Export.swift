import CADKernel
import CADModel
import Foundation
import simd

/// What a STEP file holds, read back through Open CASCADE.
public struct STEPInspection: Sendable, Equatable {
    public let solidCount: Int
    public let volume: Double
    /// Nil when the file has no solids.
    public let bounds: Bounds?
    public let names: [String]
}

extension OCCTGeometryKernel {
    public func mesh(of body: Solid, tolerance: Double) throws -> BodyMesh {
        let mesh = try Kernel.tessellate(body, tolerance: tolerance)
        return BodyMesh(positions: mesh.positions, normals: mesh.normals, indices: mesh.indices)
    }

    public func writeSTEP(_ scene: ExportScene<Solid>, to url: URL) throws {
        try Kernel.writeSTEP(
            products: scene.products.map { product in
                STEPProduct(
                    name: product.name, bodies: product.bodies.map { ($0.name, $0.body) }, color: product.color)
            },
            occurrences: scene.occurrences.map {
                STEPOccurrence(
                    name: $0.name, product: $0.product, rotation: $0.transform.rotation,
                    translation: $0.transform.translation)
            },
            name: scene.name, to: url)
    }

    /// Reads a STEP file back, for checking exports.
    public static func inspectSTEP(at url: URL) throws -> STEPInspection {
        let contents = try Kernel.readSTEP(from: url)
        let metrics = try contents.solids.map { try Kernel.metrics(of: $0) }
        var bounds: Bounds?
        for metric in metrics {
            let next = Bounds(min: metric.boundsMin, max: metric.boundsMax)
            bounds = bounds.map { Bounds(min: simd_min($0.min, next.min), max: simd_max($0.max, next.max)) } ?? next
        }
        return STEPInspection(
            solidCount: contents.solids.count, volume: metrics.reduce(0) { $0 + ($1.volume ?? 0) }, bounds: bounds,
            names: contents.names)
    }
}
