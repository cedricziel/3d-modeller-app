import Testing
@testable import CADModel

@Suite("Parameters")
struct ParameterTableTests {
    @Test("Parameters evaluate in dependency order regardless of listing order")
    func dependencyOrder() {
        let table = ParameterTable([
            Parameter(name: "half", expression: "width / 2"),
            Parameter(name: "width", expression: 60),
        ])
        #expect(table.value(of: "half") == .success(30))
        #expect(table.parameters.map(\.name) == ["half", "width"])
    }

    @Test("A cycle is reported on each member, and dependents fail without claiming the cycle")
    func cycle() {
        let table = ParameterTable([
            Parameter(name: "a", expression: "b + 1"),
            Parameter(name: "b", expression: "a * 2"),
            Parameter(name: "c", expression: "a"),
        ])
        #expect(table.value(of: "a") == .failure(.cycle(["a", "b", "a"])))
        #expect(table.value(of: "b") == .failure(.cycle(["a", "b", "a"])))
        #expect(table.value(of: "c") == .failure(.failedParameter("a")))
    }

    @Test("A parameter referring to itself is a cycle")
    func selfReference() {
        let table = ParameterTable([Parameter(name: "a", expression: "a + 1")])
        #expect(table.value(of: "a") == .failure(.cycle(["a", "a"])))
    }

    @Test("Unknown names, duplicates and invalid names are errors")
    func invalidDefinitions() {
        let table = ParameterTable([
            Parameter(name: "a", expression: "missing"),
            Parameter(name: "d", expression: 1),
            Parameter(name: "d", expression: 2),
            Parameter(name: "2x", expression: 3),
        ])
        #expect(table.value(of: "a") == .failure(.unknownName("missing")))
        #expect(table.value(of: "d") == .failure(.duplicateParameter("d")))
        #expect(table.value(of: "2x") == .failure(.invalidParameterName("2x")))
    }

    @Test("Evaluating a scalar uses the table")
    func evaluateScalar() throws {
        let table = ParameterTable([
            Parameter(name: "t", expression: 4),
            Parameter(name: "bad", expression: "1/0"),
        ])
        #expect(try table.evaluate("t * 2.5") == 10)
        #expect(throws: ExpressionError.failedParameter("bad")) { try table.evaluate("bad + 1") }
        #expect(throws: ExpressionError.unknownName("nope")) { try table.evaluate("nope") }
    }
}
