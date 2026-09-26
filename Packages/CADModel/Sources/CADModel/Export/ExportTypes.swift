import Foundation

public enum ExportFormat: String, Sendable, CaseIterable, Codable {
    case step
    case stl
    case threeMF = "3mf"

    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .step: "STEP"
        case .stl: "STL"
        case .threeMF: "3MF"
        }
    }

    /// Whether the format stores triangles rather than exact geometry.
    public var isMesh: Bool { self != .step }
}

/// What to export: the whole document, one part, one body of a part, or one placed instance.
public enum ExportTarget: Sendable, Hashable {
    /// The assembly when it places at least one instance, else every part.
    case document
    case part(UUID)
    case body(part: UUID, body: String)
    case instance(UUID)
}

public struct ExportError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }

    public var errorDescription: String? { description }
}

public struct ExportSummary: Sendable, Equatable {
    public let format: ExportFormat
    public let url: URL
    public let bytes: Int
    public let products: [String]
    public let occurrences: [String]
    public let bodyCount: Int
    /// The triangles written, for mesh formats.
    public let triangleCount: Int?
    /// What was left out, and why.
    public let skipped: [String]
}

/// The colours products are exported in, the same as `render_views` draws them.
public enum ExportPalette {
    public static let colors: [(name: String, rgb: SIMD3<Double>)] = [
        ("blue", SIMD3(0.27, 0.48, 0.85)), ("orange", SIMD3(0.93, 0.55, 0.17)), ("green", SIMD3(0.33, 0.68, 0.32)),
        ("red", SIMD3(0.85, 0.27, 0.27)), ("purple", SIMD3(0.58, 0.40, 0.80)), ("teal", SIMD3(0.20, 0.66, 0.66)),
        ("yellow", SIMD3(0.90, 0.78, 0.20)), ("pink", SIMD3(0.90, 0.47, 0.70)),
    ]

    public static func color(_ index: Int) -> SIMD3<Double> {
        colors[index % colors.count].rgb
    }
}
