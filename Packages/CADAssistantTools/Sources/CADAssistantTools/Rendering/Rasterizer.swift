import simd

/// A z-buffered raster: pixel centres sit at +0.5, depth grows away from the camera.
struct Rasterizer {
    private(set) var image: RGBAImage
    private var depth: [Float]
    private let size: Int

    init(size: Int, background: SIMD4<UInt8>) {
        self.size = size
        image = RGBAImage(width: size, height: size, fill: background)
        depth = Array(repeating: .infinity, count: size * size)
    }

    mutating func fill(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ colour: SIMD4<UInt8>) {
        let area = edge(a, b, c)
        guard abs(area) > 1e-9 else { return }
        let minX = max(0, Int((min(a.x, b.x, c.x)).rounded(.down)))
        let maxX = min(size - 1, Int((max(a.x, b.x, c.x)).rounded(.up)))
        let minY = max(0, Int((min(a.y, b.y, c.y)).rounded(.down)))
        let maxY = min(size - 1, Int((max(a.y, b.y, c.y)).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }
        for y in minY...maxY {
            for x in minX...maxX {
                let p = SIMD3<Float>(Float(x) + 0.5, Float(y) + 0.5, 0)
                let (wa, wb, wc) = (edge(b, c, p) / area, edge(c, a, p) / area, edge(a, b, p) / area)
                guard wa >= 0, wb >= 0, wc >= 0 else { continue }
                let z = wa * a.z + wb * b.z + wc * c.z
                let index = y * size + x
                if z < depth[index] {
                    depth[index] = z
                    image.set(x, y, colour)
                }
            }
        }
    }

    mutating func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ colour: SIMD4<UInt8>, depthBias: Float) {
        let steps = max(1, Int(max(abs(b.x - a.x), abs(b.y - a.y)).rounded(.up)))
        for step in 0...steps {
            let point = a + (b - a) * (Float(step) / Float(steps))
            let (x, y) = (Int(point.x.rounded(.down)), Int(point.y.rounded(.down)))
            guard (0..<size).contains(x), (0..<size).contains(y) else { continue }
            let index = y * size + x
            if point.z <= depth[index] + depthBias {
                image.set(x, y, colour)
            }
        }
    }

    private func edge(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ p: SIMD3<Float>) -> Float {
        (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
    }
}
