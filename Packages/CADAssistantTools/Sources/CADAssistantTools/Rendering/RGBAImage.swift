struct RGBAImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, fill: SIMD4<UInt8>) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = fill.x
            pixels[offset + 1] = fill.y
            pixels[offset + 2] = fill.z
            pixels[offset + 3] = fill.w
        }
    }

    func pixel(_ x: Int, _ y: Int) -> SIMD4<UInt8> {
        let offset = (y * width + x) * 4
        return SIMD4(pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
    }

    mutating func set(_ x: Int, _ y: Int, _ colour: SIMD4<UInt8>) {
        let offset = (y * width + x) * 4
        pixels[offset] = colour.x
        pixels[offset + 1] = colour.y
        pixels[offset + 2] = colour.z
        pixels[offset + 3] = colour.w
    }
}
