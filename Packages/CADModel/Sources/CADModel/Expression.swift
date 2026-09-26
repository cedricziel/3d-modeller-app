public enum ExpressionError: Error, Sendable, Hashable, CustomStringConvertible {
    case syntax(String)
    case unknownName(String)
    case cycle([String])
    case divisionByZero
    case notFinite
    case invalidParameterName(String)
    case duplicateParameter(String)
    case failedParameter(String)

    public var description: String {
        switch self {
        case .syntax(let detail): "syntax error: \(detail)"
        case .unknownName(let name): "unknown parameter '\(name)'"
        case .cycle(let names): "parameters refer to each other in a cycle: \(names.joined(separator: " → "))"
        case .divisionByZero: "division by zero"
        case .notFinite: "the result is not a finite number"
        case .invalidParameterName(let name):
            "'\(name)' is not a valid parameter name (letters, digits and _, not starting with a digit)"
        case .duplicateParameter(let name): "parameter '\(name)' is defined more than once"
        case .failedParameter(let name): "parameter '\(name)' has an error"
        }
    }
}

indirect enum Expression: Sendable, Equatable {
    case number(Double)
    case name(String)
    case negate(Expression)
    case binary(Character, Expression, Expression)

    static func parse(_ text: String) throws(ExpressionError) -> Expression {
        var parser = ExpressionParser(tokens: try ExpressionToken.tokenize(text))
        return try parser.parseAll()
    }

    func evaluate(_ lookup: (String) throws(ExpressionError) -> Double) throws(ExpressionError) -> Double {
        let value: Double
        switch self {
        case .number(let number):
            value = number
        case .name(let name):
            value = try lookup(name)
        case .negate(let operand):
            value = -(try operand.evaluate(lookup))
        case .binary(let symbol, let lhs, let rhs):
            let left = try lhs.evaluate(lookup)
            let right = try rhs.evaluate(lookup)
            switch symbol {
            case "+": value = left + right
            case "-": value = left - right
            case "*": value = left * right
            default:
                guard right != 0 else { throw .divisionByZero }
                value = left / right
            }
        }
        guard value.isFinite else { throw .notFinite }
        return value
    }
}

enum ExpressionToken: Equatable, CustomStringConvertible {
    case number(Double)
    case name(String)
    case symbol(Character)

    var description: String {
        switch self {
        case .number(let number): Scalar.format(number)
        case .name(let name): name
        case .symbol(let symbol): String(symbol)
        }
    }

    static func tokenize(_ text: String) throws(ExpressionError) -> [ExpressionToken] {
        let characters = Array(text)
        var tokens: [ExpressionToken] = []
        var index = 0
        func scan(while predicate: (Character) -> Bool) -> String {
            let start = index
            while index < characters.count, predicate(characters[index]) { index += 1 }
            return String(characters[start..<index])
        }
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
            } else if "+-*/()".contains(character) {
                tokens.append(.symbol(character))
                index += 1
            } else if character.isDigit || character == "." {
                var literal = scan { $0.isDigit || $0 == "." }
                if index < characters.count, characters[index] == "e" || characters[index] == "E" {
                    var end = index + 1
                    if end < characters.count, characters[end] == "+" || characters[end] == "-" { end += 1 }
                    let digits = end
                    while end < characters.count, characters[end].isDigit { end += 1 }
                    if end > digits {
                        literal += String(characters[index..<end])
                        index = end
                    }
                }
                guard let value = Double(literal) else { throw .syntax("'\(literal)' is not a number") }
                tokens.append(.number(value))
            } else if character.isIdentifierStart {
                tokens.append(.name(scan { $0.isIdentifierStart || $0.isDigit }))
            } else {
                throw .syntax("unexpected character '\(character)'")
            }
        }
        return tokens
    }
}

struct ExpressionParser {
    static let maximumDepth = 64

    let tokens: [ExpressionToken]
    private var position = 0
    private var depth = 0

    init(tokens: [ExpressionToken]) {
        self.tokens = tokens
    }

    mutating func parseAll() throws(ExpressionError) -> Expression {
        let expression = try parseSum()
        if let next { throw .syntax("unexpected '\(next)'") }
        return expression
    }

    private var next: ExpressionToken? { position < tokens.count ? tokens[position] : nil }

    private mutating func take(_ symbols: String) -> Character? {
        guard case .symbol(let symbol)? = next, symbols.contains(symbol) else { return nil }
        position += 1
        return symbol
    }

    private mutating func parseSum() throws(ExpressionError) -> Expression {
        var expression = try parseProduct()
        while let symbol = take("+-") {
            expression = .binary(symbol, expression, try parseProduct())
        }
        return expression
    }

    private mutating func parseProduct() throws(ExpressionError) -> Expression {
        var expression = try parseUnary()
        while let symbol = take("*/") {
            expression = .binary(symbol, expression, try parseUnary())
        }
        return expression
    }

    private mutating func parseUnary() throws(ExpressionError) -> Expression {
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maximumDepth else { throw .syntax("the expression is nested too deeply") }
        if take("-") != nil { return .negate(try parseUnary()) }
        if take("+") != nil { return try parseUnary() }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws(ExpressionError) -> Expression {
        guard let token = next else { throw .syntax("unexpected end of expression") }
        position += 1
        switch token {
        case .number(let value):
            return .number(value)
        case .name(let name):
            return .name(name)
        case .symbol("("):
            let inner = try parseSum()
            guard take(")") != nil else { throw .syntax("missing ')'") }
            return inner
        case .symbol(let symbol):
            throw .syntax("unexpected '\(symbol)'")
        }
    }
}

extension Character {
    var isDigit: Bool { isASCII && isNumber }
    var isIdentifierStart: Bool { (isASCII && isLetter) || self == "_" }
}
