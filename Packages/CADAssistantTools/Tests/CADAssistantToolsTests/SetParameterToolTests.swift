import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("set_parameter")
struct SetParameterToolTests {
    @Test("Adding a parameter appends it and reports the changed listing line")
    func adds() async throws {
        let harness = Harness()

        let result = try await harness.call("set_parameter", ["name": "width", "expression": 60])

        #expect(result.success)
        #expect(harness.document.parameters == [Parameter(name: "width", expression: 60)])
        #expect(harness.commits == ["Add Parameter width"])
        #expect(
            result.message == """
                Added parameter width = 60
                Bodies: none
                Listing changes:
                  - parameters: none
                  + parameters: width = 60
                """)
    }

    @Test("Changing a parameter rebuilds and reports the features whose status changed")
    func updatesAndReportsStatusChanges() async throws {
        let harness = Harness(Fixtures.plate())

        let result = try await harness.call("set_parameter", ["name": "width", "expression": "0"])

        #expect(result.success)
        #expect(harness.commits == ["Set Parameter width"])
        #expect(harness.document.parameters[0].expression == 0)
        #expect(result.message.contains("Status changes elsewhere:\n  Base: ok → failed: dimensions must be positive"))
        #expect(result.message.contains("  Hole: ok → skipped: depends on Base"))
        #expect(result.message.contains("+ parameters: width = 0, depth = 40"))
    }

    @Test("Expression strings are kept as expressions and numeric strings become numbers")
    func expressionStrings() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())

        _ = try await harness.call("set_parameter", ["name": "gap", "expression": "t / 4"])
        _ = try await harness.call("set_parameter", ["name": "count", "expression": " 3 "])

        #expect(
            harness.document.parameters.suffix(2) == [
                Parameter(name: "gap", expression: "t / 4"), Parameter(name: "count", expression: 3),
            ])
        #expect(harness.session.listing.contains("gap = t / 4 (= 2.5), count = 3"))
    }

    @Test("Removing an unused parameter succeeds")
    func removes() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())

        let result = try await harness.call("set_parameter", ["name": "hole_r", "remove": true])

        #expect(result.success)
        #expect(harness.commits == ["Remove Parameter hole_r"])
        #expect(!harness.document.parameters.contains { $0.name == "hole_r" })
    }

    @Test("Removing a parameter that features or parameters use is refused with every broken expression")
    func removeInUseRefused() async throws {
        let harness = Harness(Fixtures.plate())

        let message = try await harness.refused("set_parameter", ["name": "hole_d", "remove": true])

        #expect(
            message == """
                Nothing changed, because these expressions would not evaluate:
                  parameter hole_r = hole_d / 2: unknown parameter 'hole_d'
                  Hole.radius = hole_r: parameter 'hole_r' has an error
                """)
    }

    @Test("Bad expressions, cycles and bad names are refused and leave the document unchanged")
    func badInput() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())

        #expect(
            try await harness.refused("set_parameter", ["name": "a", "expression": "1 +"])?.contains("syntax error")
                == true)
        #expect(
            try await harness.refused("set_parameter", ["name": "t", "expression": "width / (depth - 40)"])?.contains(
                "parameter t = width / (depth - 40): division by zero") == true)
        #expect(
            try await harness.refused("set_parameter", ["name": "hole_d", "expression": "hole_r * 2"])?.contains(
                "cycle") == true)
        #expect(
            try await harness.refused("set_parameter", ["name": "2x", "expression": 1])?.contains(
                "not a valid parameter name") == true)
        #expect(
            try await harness.refused("set_parameter", ["name": "x"])
                == "Give 'expression' to set the parameter, or 'remove': true.")
        #expect(
            try await harness.refused("set_parameter", ["name": "t", "expression": 1, "remove": true])
                == "Give either 'expression' or 'remove', not both.")
        #expect(
            try await harness.refused("set_parameter", ["name": "nope", "remove": true])
                == "No parameter named 'nope'. Parameters: width, depth, t, hole_d, hole_r.")
        #expect(
            try await harness.refused("set_parameter", ["name": "x", "value": 1])
                == "Unknown argument 'value'. Accepted: name, expression, remove.")
        #expect(
            try await harness.refused("set_parameter", ["name": "x", "expression": true])?.contains(
                "must be a number or an expression") == true)
    }

    @Test("Setting a parameter to its current expression changes nothing and adds no undo step")
    func noChange() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())

        let result = try await harness.call("set_parameter", ["name": "t", "expression": 10])

        #expect(result.success)
        #expect(result.message == "Set parameter t = 10. Nothing changed.")
        #expect(harness.commits.isEmpty)
    }
}
