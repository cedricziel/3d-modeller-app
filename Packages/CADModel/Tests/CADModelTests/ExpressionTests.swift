import Testing
@testable import CADModel

@Suite("Expressions")
struct ExpressionTests {
    private func eval(_ text: String, _ names: [String: Double] = [:]) throws(ExpressionError) -> Double {
        try Scalar.expression(text).evaluate { (name) throws(ExpressionError) -> Double in
            guard let value = names[name] else { throw .unknownName(name) }
            return value
        }
    }

    @Test(
        "Arithmetic follows precedence and parentheses",
        arguments: [
            ("1 + 2 * 3", 7.0), ("(1 + 2) * 3", 9), ("10 / 4", 2.5), ("-3 + 5", 2), ("--2", 2), ("+4", 4),
            ("2 * -3", -6), ("1e3 / 10", 100), (".5 * 4", 2), ("8 - 2 - 1", 5), ("16 / 4 / 2", 2),
        ])
    func arithmetic(text: String, expected: Double) throws {
        #expect(try eval(text) == expected)
    }

    @Test("Names are looked up")
    func names() throws {
        #expect(try eval("width/2 + t_1", ["width": 60, "t_1": 3]) == 33)
    }

    @Test("Unknown names are reported")
    func unknownName() {
        #expect(throws: ExpressionError.unknownName("depth")) { try eval("depth * 2") }
    }

    @Test(
        "Syntax errors are reported", arguments: ["", "1 +", "(1 + 2", "1 2", "2 * * 3", "1.2.3", "3 $ 4", ")", "2e"])
    func syntax(text: String) {
        #expect {
            try eval(text)
        } throws: { error in
            if case .syntax = error as? ExpressionError { return true }
            return false
        }
    }

    @Test("Division by zero is an error")
    func divisionByZero() {
        #expect(throws: ExpressionError.divisionByZero) { try eval("1 / (2 - 2)") }
    }

    @Test("Results that overflow are not finite")
    func overflow() {
        #expect(throws: ExpressionError.notFinite) { try eval("1e308 * 10") }
        #expect(throws: ExpressionError.notFinite) { try Scalar.number(.infinity).evaluate { _ in 0 } }
    }

    @Test("Deep nesting is refused instead of overflowing the stack")
    func deepNesting() {
        let text = String(repeating: "(", count: 10_000) + "1" + String(repeating: ")", count: 10_000)
        #expect {
            try eval(text)
        } throws: { error in
            if case .syntax = error as? ExpressionError { return true }
            return false
        }
        #expect(throws: ExpressionError.self) { try eval(String(repeating: "-", count: 10_000) + "1") }
    }
}
