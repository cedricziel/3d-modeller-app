import Foundation

public enum Scalar: Sendable, Hashable {
    case number(Double)
    case expression(String)
}

extension Scalar: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let text = try? container.decode(String.self) {
            self = .expression(text)
        } else {
            throw DecodingError.typeMismatch(
                Scalar.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected a number or an expression string")
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let number): try container.encode(number)
        case .expression(let text): try container.encode(text)
        }
    }
}

extension Scalar: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByStringLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .expression(value) }
}

extension Scalar: CustomStringConvertible {
    public var description: String {
        switch self {
        case .number(let number): Scalar.format(number)
        case .expression(let text): text
        }
    }

    static func format(_ number: Double) -> String {
        if number == number.rounded(), abs(number) < 1e15 { return String(Int64(number)) }
        return String(number)
    }
}

extension Scalar {
    func evaluate(_ lookup: (String) throws(ExpressionError) -> Double) throws(ExpressionError) -> Double {
        switch self {
        case .number(let number):
            guard number.isFinite else { throw .notFinite }
            return number
        case .expression(let text):
            return try Expression.parse(text).evaluate(lookup)
        }
    }
}
