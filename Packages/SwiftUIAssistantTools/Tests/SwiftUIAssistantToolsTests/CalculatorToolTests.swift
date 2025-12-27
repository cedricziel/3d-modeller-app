import Foundation
import Testing
@testable import SwiftUIAssistantTools
import SwiftUIAssistant

@Suite("CalculatorTool Tests")
struct CalculatorToolTests {
    let calculator = CalculatorTool()

    // MARK: - Helper

    private func evaluate(_ expression: String, angleUnit: String = "degrees") async throws -> Double {
        var args: [String: JSONValue] = ["expression": .string(expression)]
        if angleUnit != "degrees" {
            args["angleUnit"] = .string(angleUnit)
        }
        let result = try await calculator.execute(arguments: args)
        guard result.success, let data = result.data, let value = data["result"]?.doubleValue else {
            throw TestError(message: result.message)
        }
        return value
    }

    private struct TestError: Error {
        let message: String
    }

    // MARK: - Basic Arithmetic

    @Test("Addition")
    func testAddition() async throws {
        #expect(try await evaluate("2 + 3") == 5)
        #expect(try await evaluate("0 + 0") == 0)
        #expect(try await evaluate("-5 + 3") == -2)
        #expect(try await evaluate("1.5 + 2.5") == 4)
    }

    @Test("Subtraction")
    func testSubtraction() async throws {
        #expect(try await evaluate("5 - 3") == 2)
        #expect(try await evaluate("3 - 5") == -2)
        #expect(try await evaluate("-3 - 2") == -5)
    }

    @Test("Multiplication")
    func testMultiplication() async throws {
        #expect(try await evaluate("3 * 4") == 12)
        #expect(try await evaluate("-3 * 4") == -12)
        #expect(try await evaluate("2.5 * 4") == 10)
        #expect(try await evaluate("0 * 100") == 0)
    }

    @Test("Division")
    func testDivision() async throws {
        #expect(try await evaluate("12 / 4") == 3)
        #expect(try await evaluate("10 / 4") == 2.5)
        #expect(try await evaluate("-12 / 4") == -3)
    }

    @Test("Division by zero")
    func testDivisionByZero() async throws {
        let result = try await calculator.execute(arguments: ["expression": .string("5 / 0")])
        #expect(result.success == false)
        #expect(result.message.contains("Division by zero"))
    }

    @Test("Power")
    func testPower() async throws {
        #expect(try await evaluate("2 ^ 3") == 8)
        #expect(try await evaluate("2 ^ 0") == 1)
        #expect(try await evaluate("4 ^ 0.5") == 2)
    }

    @Test("Modulo")
    func testModulo() async throws {
        #expect(try await evaluate("10 % 3") == 1)
        #expect(try await evaluate("12 % 4") == 0)
    }

    // MARK: - Operator Precedence

    @Test("Operator precedence")
    func testOperatorPrecedence() async throws {
        #expect(try await evaluate("2 + 3 * 4") == 14)
        #expect(try await evaluate("2 * 3 + 4") == 10)
        #expect(try await evaluate("10 - 2 * 3") == 4)
        #expect(try await evaluate("2 ^ 3 * 2") == 16)
    }

    @Test("Parentheses")
    func testParentheses() async throws {
        #expect(try await evaluate("(2 + 3) * 4") == 20)
        #expect(try await evaluate("2 * (3 + 4)") == 14)
        #expect(try await evaluate("((2 + 3) * (4 + 1))") == 25)
        #expect(try await evaluate("(10 - 2) * (3 + 1)") == 32)
    }

    // MARK: - Mathematical Functions

    @Test("Square root")
    func testSquareRoot() async throws {
        #expect(try await evaluate("sqrt(16)") == 4)
        #expect(try await evaluate("sqrt(2)") == Double.squareRoot(2)())
        #expect(try await evaluate("sqrt(0)") == 0)
    }

    @Test("Absolute value")
    func testAbsoluteValue() async throws {
        #expect(try await evaluate("abs(-5)") == 5)
        #expect(try await evaluate("abs(5)") == 5)
        #expect(try await evaluate("abs(0)") == 0)
    }

    @Test("Floor and ceil")
    func testFloorCeil() async throws {
        #expect(try await evaluate("floor(3.7)") == 3)
        #expect(try await evaluate("floor(-3.7)") == -4)
        #expect(try await evaluate("ceil(3.2)") == 4)
        #expect(try await evaluate("ceil(-3.2)") == -3)
    }

    @Test("Round")
    func testRound() async throws {
        #expect(try await evaluate("round(3.4)") == 3)
        #expect(try await evaluate("round(3.5)") == 4)
        #expect(try await evaluate("round(-3.5)") == -4)
    }

    @Test("Power function")
    func testPowFunction() async throws {
        #expect(try await evaluate("pow(2, 3)") == 8)
        #expect(try await evaluate("pow(4, 0.5)") == 2)
        #expect(try await evaluate("pow(10, 0)") == 1)
    }

    @Test("Exponential")
    func testExponential() async throws {
        let result = try await evaluate("exp(1)")
        #expect(abs(result - M_E) < 0.0001)
        #expect(try await evaluate("exp(0)") == 1)
    }

    // MARK: - Logarithms

    @Test("Natural logarithm")
    func testNaturalLog() async throws {
        #expect(try await evaluate("ln(1)") == 0)
        let lnE = try await evaluate("ln(2.718281828)")
        #expect(abs(lnE - 1) < 0.0001)
    }

    @Test("Log base 10")
    func testLog10() async throws {
        #expect(try await evaluate("log10(100)") == 2)
        #expect(try await evaluate("log10(1000)") == 3)
        #expect(try await evaluate("log10(1)") == 0)
    }

    @Test("Log base 2")
    func testLog2() async throws {
        #expect(try await evaluate("log2(8)") == 3)
        #expect(try await evaluate("log2(16)") == 4)
        #expect(try await evaluate("log2(1)") == 0)
    }

    // MARK: - Trigonometry (Degrees)

    @Test("Sine in degrees")
    func testSineDegrees() async throws {
        #expect(try await evaluate("sin(0)") == 0)
        let sin90 = try await evaluate("sin(90)")
        #expect(abs(sin90 - 1) < 0.0001)
        let sin45 = try await evaluate("sin(45)")
        #expect(abs(sin45 - 0.7071067811865476) < 0.0001)
    }

    @Test("Cosine in degrees")
    func testCosineDegrees() async throws {
        #expect(try await evaluate("cos(0)") == 1)
        let cos90 = try await evaluate("cos(90)")
        #expect(abs(cos90) < 0.0001)
        let cos60 = try await evaluate("cos(60)")
        #expect(abs(cos60 - 0.5) < 0.0001)
    }

    @Test("Tangent in degrees")
    func testTangentDegrees() async throws {
        #expect(try await evaluate("tan(0)") == 0)
        let tan45 = try await evaluate("tan(45)")
        #expect(abs(tan45 - 1) < 0.0001)
    }

    // MARK: - Trigonometry (Radians)

    @Test("Sine in radians")
    func testSineRadians() async throws {
        #expect(try await evaluate("sin(0)", angleUnit: "radians") == 0)
        let sinPiHalf = try await evaluate("sin(1.5707963267948966)", angleUnit: "radians")
        #expect(abs(sinPiHalf - 1) < 0.0001)
    }

    @Test("Cosine in radians")
    func testCosineRadians() async throws {
        #expect(try await evaluate("cos(0)", angleUnit: "radians") == 1)
        let cosPi = try await evaluate("cos(3.141592653589793)", angleUnit: "radians")
        #expect(abs(cosPi - (-1)) < 0.0001)
    }

    // MARK: - Inverse Trigonometry

    @Test("Arcsine in degrees")
    func testArcsineDegrees() async throws {
        let asin1 = try await evaluate("asin(1)")
        #expect(abs(asin1 - 90) < 0.0001)
        let asin0 = try await evaluate("asin(0)")
        #expect(abs(asin0) < 0.0001)
    }

    @Test("Arccosine in degrees")
    func testArccosineDegrees() async throws {
        let acos0 = try await evaluate("acos(0)")
        #expect(abs(acos0 - 90) < 0.0001)
        let acos1 = try await evaluate("acos(1)")
        #expect(abs(acos1) < 0.0001)
    }

    @Test("Arctangent in degrees")
    func testArctangentDegrees() async throws {
        let atan1 = try await evaluate("atan(1)")
        #expect(abs(atan1 - 45) < 0.0001)
        let atan0 = try await evaluate("atan(0)")
        #expect(abs(atan0) < 0.0001)
    }

    // MARK: - Hyperbolic Functions

    @Test("Hyperbolic sine")
    func testHyperbolicSine() async throws {
        #expect(try await evaluate("sinh(0)") == 0)
        let sinh1 = try await evaluate("sinh(1)")
        #expect(abs(sinh1 - 1.1752011936438014) < 0.0001)
    }

    @Test("Hyperbolic cosine")
    func testHyperbolicCosine() async throws {
        #expect(try await evaluate("cosh(0)") == 1)
        let cosh1 = try await evaluate("cosh(1)")
        #expect(abs(cosh1 - 1.5430806348152437) < 0.0001)
    }

    @Test("Hyperbolic tangent")
    func testHyperbolicTangent() async throws {
        #expect(try await evaluate("tanh(0)") == 0)
        let tanh1 = try await evaluate("tanh(1)")
        #expect(abs(tanh1 - 0.7615941559557649) < 0.0001)
    }

    // MARK: - Constants

    @Test("Pi constant")
    func testPiConstant() async throws {
        let result = try await evaluate("pi")
        #expect(abs(result - Double.pi) < 0.0001)
    }

    @Test("E constant")
    func testEConstant() async throws {
        let result = try await evaluate("e")
        #expect(abs(result - M_E) < 0.0001)
    }

    @Test("Constants in expressions")
    func testConstantsInExpressions() async throws {
        let result = try await evaluate("2 * pi")
        #expect(abs(result - 2 * Double.pi) < 0.0001)
    }

    // MARK: - Complex Expressions

    @Test("Nested functions")
    func testNestedFunctions() async throws {
        #expect(try await evaluate("sqrt(abs(-16))") == 4)
        #expect(try await evaluate("floor(sqrt(10))") == 3)
    }

    @Test("Combined operations")
    func testCombinedOperations() async throws {
        let result = try await evaluate("sqrt(16) + pow(2, 3)")
        #expect(result == 12)
    }

    @Test("Expressions with spaces")
    func testExpressionsWithSpaces() async throws {
        #expect(try await evaluate("  2  +  3  ") == 5)
        #expect(try await evaluate("sqrt( 16 )") == 4)
    }

    // MARK: - Error Cases

    @Test("Missing expression parameter")
    func testMissingExpression() async throws {
        let result = try await calculator.execute(arguments: [:])
        #expect(result.success == false)
        #expect(result.message.contains("Missing required parameter"))
    }

    @Test("Invalid expression")
    func testInvalidExpression() async throws {
        let result = try await calculator.execute(arguments: ["expression": .string("2 + + 3")])
        #expect(result.success == false)
    }

    @Test("Unmatched parenthesis")
    func testUnmatchedParenthesis() async throws {
        let result = try await calculator.execute(arguments: ["expression": .string("(2 + 3")])
        #expect(result.success == false)
        #expect(result.message.contains("parenthesis"))
    }

    // MARK: - Tool Metadata

    @Test("Tool has correct name and id")
    func testToolMetadata() {
        #expect(calculator.name == "calculator")
        #expect(calculator.id == "calculator")
        #expect(!calculator.description.isEmpty)
    }

    @Test("Tool has parameters defined")
    func testToolParameters() {
        let params = calculator.parameters
        #expect(params.count == 2)

        let expressionParam = params.first { $0.name == "expression" }
        #expect(expressionParam != nil)
        #expect(expressionParam?.required == true)

        let angleUnitParam = params.first { $0.name == "angleUnit" }
        #expect(angleUnitParam != nil)
        #expect(angleUnitParam?.required == false)
    }
}
