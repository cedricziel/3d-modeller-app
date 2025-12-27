import Foundation
import SwiftUIAssistant

/// Tool for performing mathematical calculations
public struct CalculatorTool: AssistantTool, Sendable {
    public let id = "calculator"
    public let name = "calculator"
    public let description = "Performs mathematical calculations. Supports basic arithmetic, trigonometry, logarithms, and more."

    public var parameters: [ToolParameter] {
        [
            .string("expression", description: "Mathematical expression to evaluate (e.g., '2 + 3 * 4', 'sin(45)', 'sqrt(16)')"),
            .enumParameter(
                "angleUnit",
                description: "Unit for trigonometric functions",
                values: ["degrees", "radians"],
                required: false
            )
        ]
    }

    public init() {}

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        guard let expression = arguments["expression"]?.stringValue else {
            return .failure("Missing required parameter: expression")
        }

        let angleUnit = arguments["angleUnit"]?.stringValue ?? "degrees"
        let useDegrees = angleUnit == "degrees"

        do {
            let result = try evaluate(expression: expression, useDegrees: useDegrees)
            return .success(
                "Result: \(formatNumber(result))",
                data: [
                    "expression": .string(expression),
                    "result": .number(result),
                    "formatted": .string(formatNumber(result)),
                    "angleUnit": .string(angleUnit)
                ]
            )
        } catch let error as CalculatorError {
            return .failure(error.message)
        } catch {
            return .failure("Calculation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Expression Evaluation

    private func evaluate(expression: String, useDegrees: Bool) throws -> Double {
        var expr = expression
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        // Evaluate functions first (before constant replacement to avoid conflicts)
        expr = try evaluateFunctions(expr, useDegrees: useDegrees)

        // Replace constants (use word boundary matching to avoid replacing inside numbers)
        expr = replaceConstants(in: expr)

        // Evaluate the arithmetic expression
        return try evaluateArithmetic(expr)
    }

    private func replaceConstants(in expression: String) -> String {
        var result = expression

        // Replace 'pi' only when it's a standalone token (not part of a number)
        // Match pi when preceded by start, operator, or open paren AND followed by end, operator, or close paren
        let piPattern = try! NSRegularExpression(pattern: "(?<=[+\\-*/^%(]|^)pi(?=[+\\-*/^%)]|$)", options: [])
        result = piPattern.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(result.startIndex..., in: result),
            withTemplate: String(Double.pi)
        )

        // Replace 'e' only when standalone (not part of scientific notation like 1e5 or function names)
        let ePattern = try! NSRegularExpression(pattern: "(?<=[+\\-*/^%(]|^)e(?=[+\\-*/^%)]|$)", options: [])
        result = ePattern.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(result.startIndex..., in: result),
            withTemplate: String(M_E)
        )

        return result
    }

    private func evaluateFunctions(_ expression: String, useDegrees: Bool) throws -> String {
        var expr = expression

        // Order matters: longer names first to avoid partial matches (e.g., "cos" matching in "acos")
        let functions: [(String, (Double) -> Double)] = [
            ("sqrt", { sqrt($0) }),
            ("abs", { abs($0) }),
            ("floor", { floor($0) }),
            ("ceil", { ceil($0) }),
            ("round", { round($0) }),
            ("log10", { log10($0) }),
            ("log2", { log2($0) }),
            ("log", { log($0) }),
            ("ln", { log($0) }),
            ("exp", { exp($0) }),
            ("asinh", { asinh($0) }),
            ("acosh", { acosh($0) }),
            ("atanh", { atanh($0) }),
            ("sinh", { sinh($0) }),
            ("cosh", { cosh($0) }),
            ("tanh", { tanh($0) }),
            ("asin", { useDegrees ? asin($0) * 180 / .pi : asin($0) }),
            ("acos", { useDegrees ? acos($0) * 180 / .pi : acos($0) }),
            ("atan", { useDegrees ? atan($0) * 180 / .pi : atan($0) }),
            ("sin", { useDegrees ? sin($0 * .pi / 180) : sin($0) }),
            ("cos", { useDegrees ? cos($0 * .pi / 180) : cos($0) }),
            ("tan", { useDegrees ? tan($0 * .pi / 180) : tan($0) })
        ]

        for (name, fn) in functions {
            while let range = expr.range(of: "\(name)(") {
                guard let closeParenIndex = findMatchingParen(in: expr, from: range.upperBound) else {
                    throw CalculatorError.unmatchedParenthesis
                }

                let argString = String(expr[range.upperBound..<closeParenIndex])
                let argExpr = try evaluateFunctions(argString, useDegrees: useDegrees)
                let argValue = try evaluateArithmetic(argExpr)
                let result = fn(argValue)

                let fullRange = range.lowerBound...closeParenIndex
                expr.replaceSubrange(fullRange, with: String(result))
            }
        }

        // Handle power function: pow(base, exponent)
        while let range = expr.range(of: "pow(") {
            guard let closeParenIndex = findMatchingParen(in: expr, from: range.upperBound) else {
                throw CalculatorError.unmatchedParenthesis
            }

            let argString = String(expr[range.upperBound..<closeParenIndex])
            let args = argString.split(separator: ",").map { String($0) }
            guard args.count == 2 else {
                throw CalculatorError.invalidArguments("pow requires 2 arguments")
            }

            let base = try evaluateArithmetic(try evaluateFunctions(args[0], useDegrees: useDegrees))
            let exponent = try evaluateArithmetic(try evaluateFunctions(args[1], useDegrees: useDegrees))
            let result = pow(base, exponent)

            let fullRange = range.lowerBound...closeParenIndex
            expr.replaceSubrange(fullRange, with: String(result))
        }

        return expr
    }

    private func findMatchingParen(in str: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var index = start

        while index < str.endIndex {
            let char = str[index]
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = str.index(after: index)
        }

        return nil
    }

    private func evaluateArithmetic(_ expression: String) throws -> Double {
        var expr = expression

        // Handle parentheses first
        while let openParen = expr.lastIndex(of: "(") {
            guard let closeParen = expr[openParen...].firstIndex(of: ")") else {
                throw CalculatorError.unmatchedParenthesis
            }

            let innerStart = expr.index(after: openParen)
            let innerExpr = String(expr[innerStart..<closeParen])
            let innerResult = try evaluateArithmetic(innerExpr)

            expr.replaceSubrange(openParen...closeParen, with: String(innerResult))
        }

        // Tokenize
        let tokens = try tokenize(expr)

        // Evaluate with operator precedence
        return try evaluateTokens(tokens)
    }

    private func tokenize(_ expression: String) throws -> [Token] {
        var tokens: [Token] = []
        var numberBuffer = ""
        var index = expression.startIndex

        while index < expression.endIndex {
            let char = expression[index]

            if char.isNumber || char == "." {
                numberBuffer.append(char)
            } else if (char == "e" || char == "E") && !numberBuffer.isEmpty && numberBuffer.last?.isNumber == true {
                // Scientific notation (e.g., 1e5, 2.5e-10)
                numberBuffer.append(char)
            } else if char == "-" && numberBuffer.isEmpty && (tokens.isEmpty || tokens.last?.isOperator == true) {
                // Negative number: only if buffer is empty AND (no tokens yet OR last token is operator)
                numberBuffer.append(char)
            } else if char == "-" && !numberBuffer.isEmpty && (numberBuffer.last == "e" || numberBuffer.last == "E") {
                // Negative exponent in scientific notation (e.g., 1e-5)
                numberBuffer.append(char)
            } else if char == "+" && !numberBuffer.isEmpty && (numberBuffer.last == "e" || numberBuffer.last == "E") {
                // Positive exponent in scientific notation (e.g., 1e+5)
                numberBuffer.append(char)
            } else {
                // Flush number buffer first
                if !numberBuffer.isEmpty {
                    guard let num = Double(numberBuffer) else {
                        throw CalculatorError.invalidNumber(numberBuffer)
                    }
                    tokens.append(.number(num))
                    numberBuffer = ""
                }

                if let op = Operator(rawValue: char) {
                    tokens.append(.op(op))
                } else if !char.isWhitespace {
                    throw CalculatorError.invalidCharacter(char)
                }
            }

            index = expression.index(after: index)
        }

        if !numberBuffer.isEmpty {
            guard let num = Double(numberBuffer) else {
                throw CalculatorError.invalidNumber(numberBuffer)
            }
            tokens.append(.number(num))
        }

        return tokens
    }

    private func evaluateTokens(_ tokens: [Token]) throws -> Double {
        guard !tokens.isEmpty else {
            throw CalculatorError.emptyExpression
        }

        // Convert to postfix (Shunting Yard algorithm) and evaluate
        var output: [Double] = []
        var operators: [Operator] = []

        for token in tokens {
            switch token {
            case .number(let value):
                output.append(value)

            case .op(let op):
                while let lastOp = operators.last, lastOp.precedence >= op.precedence {
                    operators.removeLast()
                    try applyOperator(lastOp, to: &output)
                }
                operators.append(op)
            }
        }

        while let op = operators.popLast() {
            try applyOperator(op, to: &output)
        }

        guard output.count == 1 else {
            throw CalculatorError.invalidExpression
        }

        return output[0]
    }

    private func applyOperator(_ op: Operator, to stack: inout [Double]) throws {
        guard stack.count >= 2 else {
            throw CalculatorError.invalidExpression
        }

        let b = stack.removeLast()
        let a = stack.removeLast()

        let result: Double
        switch op {
        case .add: result = a + b
        case .subtract: result = a - b
        case .multiply: result = a * b
        case .divide:
            guard b != 0 else {
                throw CalculatorError.divisionByZero
            }
            result = a / b
        case .power: result = pow(a, b)
        case .modulo:
            guard b != 0 else {
                throw CalculatorError.divisionByZero
            }
            result = a.truncatingRemainder(dividingBy: b)
        }

        stack.append(result)
    }

    private func formatNumber(_ value: Double) -> String {
        if value.isNaN {
            return "NaN"
        }
        if value.isInfinite {
            return value > 0 ? "Infinity" : "-Infinity"
        }
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        // Remove trailing zeros
        let formatted = String(format: "%.10g", value)
        return formatted
    }

    // MARK: - Supporting Types

    private enum Token {
        case number(Double)
        case op(Operator)

        var isOperator: Bool {
            if case .op = self { return true }
            return false
        }
    }

    private enum Operator: Character {
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"
        case power = "^"
        case modulo = "%"

        var precedence: Int {
            switch self {
            case .add, .subtract: return 1
            case .multiply, .divide, .modulo: return 2
            case .power: return 3
            }
        }
    }

    private enum CalculatorError: Error {
        case emptyExpression
        case invalidExpression
        case invalidNumber(String)
        case invalidCharacter(Character)
        case invalidArguments(String)
        case unmatchedParenthesis
        case divisionByZero

        var message: String {
            switch self {
            case .emptyExpression:
                return "Empty expression"
            case .invalidExpression:
                return "Invalid expression"
            case .invalidNumber(let str):
                return "Invalid number: \(str)"
            case .invalidCharacter(let char):
                return "Invalid character: \(char)"
            case .invalidArguments(let msg):
                return msg
            case .unmatchedParenthesis:
                return "Unmatched parenthesis"
            case .divisionByZero:
                return "Division by zero"
            }
        }
    }
}
