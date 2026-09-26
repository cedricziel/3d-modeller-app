import CADModel
import Foundation
import simd

public struct RenderBody: Sendable {
    public let mesh: BodyMesh
    /// Linear RGB, each component 0…1.
    public let colour: SIMD3<Float>

    public init(mesh: BodyMesh, colour: SIMD3<Float>) {
        self.mesh = mesh
        self.colour = colour
    }
}

public struct RenderedView: Sendable, Equatable {
    public let view: ViewDirection
    public let png: Data
    public let millimetresPerPixel: Double

    public init(view: ViewDirection, png: Data, millimetresPerPixel: Double) {
        self.view = view
        self.png = png
        self.millimetresPerPixel = millimetresPerPixel
    }
}

/// Draws tessellated bodies with flat shading and feature lines in software, so it works without a window, GPU or
/// Metal device (command line, CI).
public enum ViewRenderer {
    public static let size = 512
    static let margin: Float = 0.06
    static let background = SIMD4<UInt8>(245, 245, 245, 255)
    static let lineColour = SIMD4<UInt8>(35, 35, 35, 255)
    /// Mesh edges whose two triangles meet at more than this angle are drawn; the facets of curved faces stay below.
    static let creaseCosine: Float = cos(35 * .pi / 180)

    public static func render(_ bodies: [RenderBody], views: [ViewDirection]) -> [RenderedView] {
        views.compactMap { view in
            let (image, millimetresPerPixel) = image(bodies, view: view, size: size)
            return PNG.encode(image).map {
                RenderedView(view: view, png: $0, millimetresPerPixel: Double(millimetresPerPixel))
            }
        }
    }

    static func image(_ bodies: [RenderBody], view: ViewDirection, size: Int) -> (
        image: RGBAImage, millimetresPerPixel: Float
    ) {
        let (right, up, forward) = view.basis
        var low = SIMD2<Float>(repeating: .infinity)
        var high = SIMD2<Float>(repeating: -.infinity)
        var nearest = Float.infinity
        var farthest = -Float.infinity
        for body in bodies {
            for position in body.mesh.positions {
                let screen = SIMD2(simd_dot(position, right), simd_dot(position, up))
                low = simd_min(low, screen)
                high = simd_max(high, screen)
                nearest = min(nearest, simd_dot(position, forward))
                farthest = max(farthest, simd_dot(position, forward))
            }
        }
        var raster = Rasterizer(size: size, background: background)
        guard low.x.isFinite else { return (raster.image, 0) }
        let span = max(high.x - low.x, high.y - low.y, 1e-3)
        let scale = Float(size) * (1 - 2 * margin) / span
        let centre = (low + high) / 2
        let project = { (position: SIMD3<Float>) -> SIMD3<Float> in
            let screen = SIMD2(simd_dot(position, right), simd_dot(position, up)) - centre
            return SIMD3(
                Float(size) / 2 + screen.x * scale, Float(size) / 2 - screen.y * scale, simd_dot(position, forward))
        }
        let light = simd_normalize(-forward + 0.6 * up - 0.25 * right)
        var lines: [(SIMD3<Float>, SIMD3<Float>)] = []
        for body in bodies {
            let mesh = body.mesh
            let normals = triangleNormals(mesh)
            for (triangle, normal) in normals.enumerated() {
                let corners = (0..<3).map { project(mesh.positions[Int(mesh.indices[triangle * 3 + $0])]) }
                let shade = 0.35 + 0.65 * abs(simd_dot(normal, light))
                let colour = simd_clamp(body.colour * shade, SIMD3(repeating: 0), SIMD3(repeating: 1)) * 255
                raster.fill(
                    corners[0], corners[1], corners[2],
                    SIMD4(SIMD3<UInt8>(colour.rounded(.toNearestOrAwayFromZero)), 255))
            }
            lines += featureLines(mesh, normals).map { (project($0.0), project($0.1)) }
        }
        let bias = 2 / scale + (farthest - nearest) * 1e-3
        for (start, end) in lines {
            raster.line(start, end, lineColour, depthBias: bias)
        }
        return (raster.image, 1 / scale)
    }

    private static func triangleNormals(_ mesh: BodyMesh) -> [SIMD3<Float>] {
        (0..<mesh.triangleCount).map { triangle in
            let p = (0..<3).map { mesh.positions[Int(mesh.indices[triangle * 3 + $0])] }
            let normal = simd_cross(p[1] - p[0], p[2] - p[0])
            return simd_length(normal) > 0 ? simd_normalize(normal) : .zero
        }
    }

    /// Mesh edges on an open border or a crease. Edges are matched by position because every face of a body has
    /// its own vertices; the unsigned angle ignores the winding, which is not consistent across faces.
    private static func featureLines(_ mesh: BodyMesh, _ normals: [SIMD3<Float>]) -> [(SIMD3<Float>, SIMD3<Float>)] {
        struct Key: Hashable {
            let a: SIMD3<Int32>
            let b: SIMD3<Int32>
        }
        func quantized(_ point: SIMD3<Float>) -> SIMD3<Int32> {
            SIMD3<Int32>((point * 1e4).rounded(.toNearestOrAwayFromZero))
        }
        var triangles: [Key: [Int]] = [:]
        var ends: [Key: (SIMD3<Float>, SIMD3<Float>)] = [:]
        for triangle in 0..<mesh.triangleCount {
            for corner in 0..<3 {
                let p = mesh.positions[Int(mesh.indices[triangle * 3 + corner])]
                let q = mesh.positions[Int(mesh.indices[triangle * 3 + (corner + 1) % 3])]
                let (a, b) = (quantized(p), quantized(q))
                let ordered = (a.x, a.y, a.z) < (b.x, b.y, b.z)
                let key = ordered ? Key(a: a, b: b) : Key(a: b, b: a)
                triangles[key, default: []].append(triangle)
                ends[key] = (p, q)
            }
        }
        return triangles.compactMap { key, sharing in
            let isFeature =
                sharing.count == 1
                || sharing.dropFirst().contains { abs(simd_dot(normals[$0], normals[sharing[0]])) < creaseCosine }
            return isFeature ? ends[key] : nil
        }
    }
}
