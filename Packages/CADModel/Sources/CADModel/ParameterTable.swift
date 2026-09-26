public struct Parameter: Codable, Sendable, Hashable {
    public var name: String
    public var expression: Scalar

    public init(name: String, expression: Scalar) {
        self.name = name
        self.expression = expression
    }
}

public struct EvaluatedParameter: Sendable, Equatable {
    public let name: String
    public let expression: Scalar
    public let value: Result<Double, ExpressionError>
}

public struct ParameterTable: Sendable, Equatable {
    public let parameters: [EvaluatedParameter]
    private let values: [String: Result<Double, ExpressionError>]

    public init(_ definitions: [Parameter]) {
        var expressions: [String: Scalar] = [:]
        var duplicates: Set<String> = []
        for definition in definitions
        where expressions.updateValue(definition.expression, forKey: definition.name) != nil {
            duplicates.insert(definition.name)
        }
        var resolved: [String: Result<Double, ExpressionError>] = [:]

        func resolve(_ name: String, path: [String]) -> Result<Double, ExpressionError> {
            if let known = resolved[name] { return known }
            if let start = path.firstIndex(of: name) { return .failure(.cycle(Array(path[start...]) + [name])) }
            let result: Result<Double, ExpressionError>
            if duplicates.contains(name) {
                result = .failure(.duplicateParameter(name))
            } else if !ParameterTable.isValidName(name) {
                result = .failure(.invalidParameterName(name))
            } else {
                let path = path + [name]
                result = Result { () throws(ExpressionError) -> Double in
                    try expressions[name, default: 0].evaluate { (reference) throws(ExpressionError) -> Double in
                        guard expressions[reference] != nil else { throw .unknownName(reference) }
                        switch resolve(reference, path: path) {
                        case .success(let value): return value
                        case .failure(.cycle(let cycle)) where cycle.contains(name): throw .cycle(cycle)
                        case .failure: throw .failedParameter(reference)
                        }
                    }
                }
            }
            resolved[name] = result
            return result
        }

        parameters = definitions.map {
            EvaluatedParameter(name: $0.name, expression: $0.expression, value: resolve($0.name, path: []))
        }
        values = resolved
    }

    public func value(of name: String) -> Result<Double, ExpressionError>? {
        values[name]
    }

    public func evaluate(_ scalar: Scalar) throws(ExpressionError) -> Double {
        try scalar.evaluate { (name) throws(ExpressionError) -> Double in
            switch values[name] {
            case .success(let value)?: return value
            case .failure?: throw .failedParameter(name)
            case nil: throw .unknownName(name)
            }
        }
    }

    static func isValidName(_ name: String) -> Bool {
        guard let first = name.first, first.isIdentifierStart else { return false }
        return name.allSatisfy { $0.isIdentifierStart || $0.isDigit }
    }
}
