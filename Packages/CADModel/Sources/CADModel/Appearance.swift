import Foundation

/// An sRGB colour with 8 bits per channel, written as "#RRGGBB".
public struct HexColor: Sendable, Hashable, Codable, CustomStringConvertible {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Six hex digits, with or without a leading #, in either case.
    public init?(_ text: String) {
        let digits = text.hasPrefix("#") ? text.dropFirst() : Substring(text)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
            return nil
        }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    public var description: String {
        hex
    }

    /// Red, green and blue in 0…1.
    public var rgb: SIMD3<Double> {
        SIMD3(Double(red), Double(green), Double(blue)) / 255
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let color = HexColor(text) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "'\(text)' is not a colour such as #2E7D32"
                )
            )
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

public struct AppearanceError: Error, Sendable, Equatable, CustomStringConvertible {
    public let description: String
}

/// How a part or an instance looks: its colour and, optionally, how metallic and how rough its surface is.
public struct Appearance: Sendable, Hashable, Codable, CustomStringConvertible {
    public private(set) var color: HexColor
    /// 0 (dielectric) … 1 (metal); nil leaves it to the viewer.
    public private(set) var metallic: Double?
    /// 0 (mirror) … 1 (matte); nil leaves it to the viewer.
    public private(set) var roughness: Double?

    public init(color: HexColor) {
        self.color = color
    }

    public init(color: HexColor, metallic: Double? = nil, roughness: Double? = nil) throws(AppearanceError) {
        try Self.check(metallic, "metallic")
        try Self.check(roughness, "roughness")
        self.color = color
        self.metallic = metallic
        self.roughness = roughness
    }

    private enum CodingKeys: String, CodingKey { case color, metallic, roughness }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                color: container.decode(HexColor.self, forKey: .color),
                metallic: container.decodeIfPresent(Double.self, forKey: .metallic),
                roughness: container.decodeIfPresent(Double.self, forKey: .roughness)
            )
        } catch let error as AppearanceError {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: error.description)
            )
        }
    }

    /// "#2E7D32", followed by the factors that are set: "#2E7D32 metallic 0.8 roughness 0.3".
    public var description: String {
        var text = color.hex
        if let metallic {
            text += " metallic \(Self.format(metallic))"
        }
        if let roughness {
            text += " roughness \(Self.format(roughness))"
        }
        return text
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    private static func check(_ value: Double?, _ name: String) throws(AppearanceError) {
        guard let value else { return }
        guard value.isFinite, (0...1).contains(value) else {
            throw AppearanceError(description: "\(name) must be between 0 and 1, not \(value)")
        }
    }
}
