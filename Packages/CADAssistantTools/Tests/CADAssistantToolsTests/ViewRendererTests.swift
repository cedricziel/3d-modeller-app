import CADModel
import Foundation
import ImageIO
import Testing

@testable import CADAssistantTools

@Suite("View renderer")
struct ViewRendererTests {
    static let blue = SIMD3<Float>(0.2, 0.4, 0.9)

    /// An axis-aligned box with its own vertices per face, as the kernel tessellates.
    static func boxMesh(_ size: SIMD3<Float>, at origin: SIMD3<Float> = .zero) -> BodyMesh {
        let corners = (0..<8).map { (index: Int) -> SIMD3<Float> in
            let x = Float(index & 1)
            let y = Float((index >> 1) & 1)
            let z = Float((index >> 2) & 1)
            return origin + size * SIMD3<Float>(x, y, z)
        }
        let quads = [[0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6], [0, 1, 3, 2], [4, 6, 7, 5]]
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for quad in quads {
            let base = UInt32(positions.count)
            positions += quad.map { corners[$0] }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return BodyMesh(positions: positions, normals: [], indices: indices)
    }

    private func image(_ mesh: BodyMesh, _ view: ViewDirection) -> RGBAImage {
        ViewRenderer.image([RenderBody(mesh: mesh, colour: Self.blue)], view: view, size: 512).image
    }

    private func isBackground(_ pixel: SIMD4<UInt8>) -> Bool { pixel == ViewRenderer.background }
    private func isBody(_ pixel: SIMD4<UInt8>) -> Bool { Int(pixel.z) > Int(pixel.x) + 40 }

    @Test("From the top a cube fills the middle of the image and leaves the corners empty")
    func cubeFromTop() {
        let image = image(Self.boxMesh(SIMD3(10, 10, 10)), .top)

        #expect(image.width == 512 && image.height == 512)
        #expect(isBody(image.pixel(256, 256)))
        #expect(isBody(image.pixel(40, 40)))
        #expect(isBackground(image.pixel(10, 10)))
        #expect(isBackground(image.pixel(500, 500)))
    }

    @Test("Feature edges are drawn dark along the outline")
    func outline() {
        let image = image(Self.boxMesh(SIMD3(10, 10, 10)), .top)
        let column = (20...40).map { image.pixel($0, 256) }

        #expect(column.contains { $0.x < 80 && $0.y < 80 && $0.z < 80 })
    }

    @Test("From the front a long bar is wider than tall")
    func barFromFront() {
        let image = image(Self.boxMesh(SIMD3(40, 10, 10)), .front)
        let row = (0..<512).count { isBody(image.pixel($0, 256)) }
        let column = (0..<512).count { isBody(image.pixel(256, $0)) }

        #expect(row > 3 * column)
    }

    @Test("The iso view shows the top, front and right faces in three shades")
    func isoShades() {
        let image = image(Self.boxMesh(SIMD3(10, 10, 10)), .iso)
        var shades = Set<SIMD4<UInt8>>()
        for y in stride(from: 0, to: 512, by: 4) {
            for x in stride(from: 0, to: 512, by: 4) where isBody(image.pixel(x, y)) {
                shades.insert(image.pixel(x, y))
            }
        }

        #expect(shades.count == 3)
    }

    @Test("Each view is encoded as a 512 × 512 PNG with its scale")
    func png() throws {
        let views = ViewRenderer.render(
            [RenderBody(mesh: Self.boxMesh(SIMD3(10, 20, 30)), colour: Self.blue)], views: [.top, .iso])

        #expect(views.map(\.view) == [.top, .iso])
        let source = try #require(CGImageSourceCreateWithData(views[0].png as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 512 && decoded.height == 512)
        #expect(abs(views[0].millimetresPerPixel - 20 / (512 * 0.88)) < 1e-6)
    }

    @Test("A mesh with a non-finite position is skipped instead of crashing the renderer")
    func nonFiniteMesh() {
        var broken = Self.boxMesh(SIMD3(1, 1, 1))
        broken.positions[0] = SIMD3(.nan, 0, 0)
        let far = Self.boxMesh(SIMD3(1, 1, 1), at: SIMD3(1e6, 0, 0))

        let result = ViewRenderer.image(
            [RenderBody(mesh: broken, colour: Self.blue), RenderBody(mesh: far, colour: Self.blue)], view: .top,
            size: 64)

        #expect(result.millimetresPerPixel > 0)
    }
}
