import AppKit
import CADModel
import SwiftUI

extension HexColor {
    /// The nearest 8-bit sRGB colour; nil when the colour cannot be expressed in sRGB.
    init?(_ color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func channel(_ value: CGFloat) -> UInt8 {
            UInt8((min(max(value, 0), 1) * 255).rounded())
        }
        self.init(
            red: channel(srgb.redComponent), green: channel(srgb.greenComponent), blue: channel(srgb.blueComponent)
        )
    }
}

extension Color {
    init(_ hex: HexColor) {
        self.init(.sRGB, red: hex.rgb.x, green: hex.rgb.y, blue: hex.rgb.z)
    }
}

extension NSColor {
    convenience init(_ hex: HexColor) {
        self.init(srgbRed: hex.rgb.x, green: hex.rgb.y, blue: hex.rgb.z, alpha: 1)
    }
}
