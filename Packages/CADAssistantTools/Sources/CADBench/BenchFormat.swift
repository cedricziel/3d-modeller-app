import Foundation

enum BenchFormat {
    static func number(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == 0 { return "0" }
        var text = String(format: "%.3f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func vector(_ value: SIMD3<Double>) -> String {
        "(\(number(value.x)), \(number(value.y)), \(number(value.z)))"
    }

    static func percent(_ fraction: Double) -> String { "\(number(fraction * 100))%" }
}
