import CADModel
import CADModelKernel
import CoreGraphics
import Foundation
import ImageIO
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("render_views")
struct RenderViewsToolTests {
    private func harness() async throws -> Harness {
        let harness = Harness()
        _ = try await harness.call(
            "add_feature", ["name": "Base", "type": "box", "width": 60, "depth": 40, "height": 10])
        _ = try await harness.call(
            "add_feature", ["name": "Knob", "type": "sphere", "radius": 3, "placement": ["translation": [0, 0, 20]]])
        return harness
    }

    @Test("All four views come back as captioned PNG images, and the text names each body's colour")
    func allViews() async throws {
        let result = try await harness().call("render_views", [:])

        #expect(result.success)
        #expect(
            result.message
                == "Rendered 4 views, 512 × 512 px each: Body1 (Plate) blue, Body2 (Plate) orange. Lengths in mm.")
        #expect(
            result.images.map { $0.caption?.components(separatedBy: ",").first } == [
                "iso: seen from +X −Y +Z", "top: looking down −Z", "front: looking along +Y at the −Y side",
                "right: looking along −X at the +X side",
            ])
        #expect(result.images.allSatisfy { $0.mediaType == "image/png" && $0.data.starts(with: [0x89, 0x50]) })
        #expect(result.images[0].caption?.hasSuffix(" mm per pixel") == true)
    }

    @Test("A subset of views can be asked for; unknown views are refused")
    func someViews() async throws {
        let harness = try await harness()

        let top = try await harness.call("render_views", ["views": ["top"]])

        #expect(top.images.count == 1)
        #expect(
            try await harness.refused("render_views", ["views": ["side"]])
                == "Unknown view 'side'. Views: iso, top, front, right.")
    }

    @Test("A body without a mesh is left out and named")
    func rendersWithoutBrokenBody() async throws {
        var kernel = FakeKernel()
        kernel.meshFails = { $0.volume == 8 }
        let session = CADSession(
            document: CADDocument(parts: [
                Part(name: "P", features: [Fixtures.box("A", 1, 1, 1), Fixtures.box("B", 2, 2, 2)])
            ]), kernel: kernel)

        let rendering = await session.renderViews([.top])

        #expect(rendering.views.count == 1)
        #expect(
            rendering.text
                == "Rendered 1 view, 512 × 512 px each: Body1 (P) blue. Lengths in mm. Not shown: Body2 (P) (no mesh for this body)."
        )
    }

    @Test("An instance body without a mesh is named while the rest of the instance is shown")
    func instanceBodyWithoutMesh() async throws {
        var kernel = FakeKernel()
        kernel.meshFails = { $0.volume == 8 }
        let part = Part(name: "P", features: [Fixtures.box("A", 1, 1, 1), Fixtures.box("B", 2, 2, 2)])
        let session = CADSession(
            document: CADDocument(
                parts: [part], assembly: Assembly(instances: [Instance(name: "Base", part: part.id, grounded: true)])),
            kernel: kernel)

        let rendering = await session.renderViews([.top])

        #expect(rendering.views.count == 1)
        #expect(rendering.text.hasPrefix("Rendered 1 view, 512 × 512 px each: Base (P) blue. Lengths in mm."))
        #expect(rendering.text.hasSuffix(" Not shown: Base/Body2 (P) (no mesh for this body)."), "\(rendering.text)")
    }

    @Test("Appearances replace the palette; the text names each colour")
    func appearanceCaptions() async {
        let ornament = Part(
            name: "Ornament", features: [Fixtures.box("A", 1, 1, 1)],
            appearance: Appearance(color: HexColor(red: 0x2E, green: 0x7D, blue: 0x32))
        )
        let plain = Part(name: "Plain", features: [Fixtures.box("B", 2, 2, 2)])
        let red = Appearance(color: HexColor(red: 0xC6, green: 0x28, blue: 0x28))
        let document = CADDocument(
            parts: [ornament, plain],
            assembly: Assembly(instances: [
                Instance(name: "O1", part: ornament.id), Instance(name: "O2", part: ornament.id, appearance: red),
                Instance(name: "P1", part: plain.id),
            ])
        )
        let session = CADSession(document: document, kernel: FakeKernel())

        let assembly = await session.renderViews([.top])
        let parts = await session.renderViews([.top], show: .parts)

        #expect(
            assembly.text
                == "Rendered 1 view, 512 × 512 px each: O1 (Ornament) #2E7D32, O2 (Ornament) #C62828, P1 (Plain) green. "
                + "Lengths in mm."
        )
        #expect(parts.text.contains(": Body1 (Ornament) #2E7D32, Body1 (Plain) orange."))
    }

    @Test("On the real kernel a coloured part is drawn in its colour")
    func appearancePixels() async throws {
        let part = Part(
            name: "Plate", features: [Fixtures.box("Plate", 60, 40, 10)],
            appearance: Appearance(color: HexColor(red: 0xC6, green: 0x28, blue: 0x28))
        )
        let session = CADSession(document: CADDocument(parts: [part]), kernel: OCCTGeometryKernel())

        let rendering = await session.renderViews([.top])
        let png = try #require(rendering.views.first?.png)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixels = try #require(RGBA(image))

        for y in stride(from: 236, through: 276, by: 10) {
            for x in stride(from: 216, through: 296, by: 10) {
                let pixel = pixels.at(x, y)
                #expect(pixel.x > 2 * pixel.y && pixel.x > 2 * pixel.z && pixel.x > 60, "(\(x), \(y)) is \(pixel)")
            }
        }
    }

    @Test("An empty model gives text and no images")
    func nothingToRender() async throws {
        let result = try await Harness().call("render_views", [:])

        #expect(result.success)
        #expect(result.images.isEmpty)
        #expect(result.message == "Nothing to render: the model has no bodies.")
    }

    @Test("On the real kernel the top view of a drilled plate shows the hole")
    func realKernel() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "Plate")]), kernel: OCCTGeometryKernel())
        let tools = Dictionary(uniqueKeysWithValues: CADTools.all(session: session).map { ($0.name, $0) })
        _ = try await tools["add_feature"]!.execute(arguments: [
            "name": "Plate", "type": "box", "width": 60, "depth": 40, "height": 10,
        ])
        _ = try await tools["add_feature"]!.execute(arguments: [
            "name": "Hole", "type": "cylinder", "radius": 5, "height": 10,
            "placement": ["translation": ["x": 30, "y": 20]], "operation": "cut", "body": "Body1",
        ])

        let result = try await tools["render_views"]!.execute(arguments: ["views": ["top"]])
        let png = try #require(result.images.first?.data)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixels = try #require(RGBA(image))

        #expect(pixels.at(256, 256) == SIMD3(245, 245, 245))
        #expect(pixels.at(356, 256) != SIMD3(245, 245, 245))
        #expect(pixels.at(5, 5) == SIMD3(245, 245, 245))
    }
}

/// The RGB bytes of a decoded image.
private struct RGBA {
    let width: Int
    let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard
            let context = CGContext(
                data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        self.bytes = bytes
    }

    func at(_ x: Int, _ y: Int) -> SIMD3<Int> {
        let offset = (y * width + x) * 4
        return SIMD3(Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }
}
