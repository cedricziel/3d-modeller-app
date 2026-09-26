import CADModel

enum Format {
    static func number(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == 0 { return "0" }
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int64(rounded)) }
        return String(rounded)
    }

    static func point(_ point: SIMD3<Double>) -> String {
        "(\(number(point.x)), \(number(point.y)), \(number(point.z)))"
    }

    /// The scalar as written; compound expressions get parentheses so they read unambiguously next to other text.
    static func operand(_ scalar: Scalar) -> String {
        guard case .expression(let text) = scalar else { return scalar.description }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let isAtom = trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
        return isAtom ? trimmed : "(\(trimmed))"
    }

    static func vector(_ vector: Vector3) -> String {
        "(\(vector.x), \(vector.y), \(vector.z))"
    }
}
