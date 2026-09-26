# CAD 02: Document model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the RealityKit scene model with a parametric CAD document (`.cadmodel`): parameters with expressions, parts with feature trees (primitives, booleans, transforms), and a rebuild engine that replays features off the main actor into bodies, metrics and meshes that the app displays.

**Architecture:** A new package `Packages/CADModel` with two targets. `CADModel` is pure Swift: the Codable document, the expression evaluator, the `GeometryKernel` protocol and the `RebuildEngine`. `CADModelKernel` holds `OCCTGeometryKernel`, the adapter that conforms `CADKernel` to `GeometryKernel` and converts degrees to radians at the boundary. The app keeps the document as a value inside a `ReferenceFileDocument`, registers every edit with the window's `UndoManager`, rebuilds with `.task(id:)` on every change, and draws the `RebuildResult` meshes.

**Tech Stack:** Swift 6 (tools 6.1 for the package), Swift Testing, SwiftUI, RealityKit, CADKernel (OCCTSwift 3.0.0 behind it).

**Spec:** `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md` (sections "Document", "Rebuild", PR-stack row 2), with `docs/superpowers/specs/2026-09-26-geometry-kernel.md` as background.

## Global Constraints

- macOS 26, Apple Silicon only (`ARCHS: arm64`), Swift 6 strict concurrency. Use `xcrun swift`, never bare `swift`.
- Only `CADKernel` imports OCCTSwift. `CADModel` imports nothing but Foundation (and Synchronization in tests).
- No C++ exception may cross into Swift. Every kernel failure becomes a typed error, here a `FeatureStatus.failed`.
- The agent-facing surface (document, rebuild) runs without the app or any UI.
- Every PR in the stack builds, passes its tests and leaves `main` shippable on its own.
- Millimetres in the model; the viewport scales to RealityKit metres.
- Old model dropped with no backward compatibility: `SceneManager`, `.scene3d`, `CreatePrimitiveTool` and its siblings go.
- Tests use Swift Testing (`@Suite`, `@Test`, `#expect`). App test module: `@testable import _D_Modeller`.

## Conventions fixed by this plan

- JSON: `{ "format": 1, "units": "mm", "parameters": [...], "parts": [...], "assembly": null }`, sorted keys, pretty-printed. `format` must be `1` and `units` must be `"mm"` or opening fails.
- Every numeric field is a `Scalar`: a JSON number (`10`) or an expression string (`"width/2 + 1"`). It re-encodes in the form it was read.
- Expressions: numbers (with optional exponent), `+ - * /`, unary minus/plus, parentheses, parameter names (`[A-Za-z_][A-Za-z0-9_]*`). Nesting deeper than 64 levels is a syntax error.
- Feature JSON is flat with a `type` discriminator:
  - `{"type":"box","width":60,"depth":40,"height":10,"placement":{…},"operation":{"mode":"newBody"}}` — box width runs along X, depth along Y, height along Z; corner at the local origin.
  - `cylinder(radius,height)`, `cone(bottomRadius,topRadius,height)`: base centred on the local origin, axis +Z. `sphere(radius)`, `torus(majorRadius,minorRadius)`: centred on the origin.
  - `{"type":"boolean","operation":"subtract","target":"Body1","tools":["Body2","Body3"]}`
  - `{"type":"transform","body":"Body1","placement":{…}}`
- Placement JSON: `{"translation":{"x":0,"y":0,"z":0},"rotationAxis":{"x":0,"y":0,"z":1},"rotationDegrees":0}`; every key optional (identity defaults). A placement rotates about the local origin, then translates.
- Solid operation JSON: `{"mode":"newBody"}` (default when absent), or `{"mode":"join"|"cut"|"intersect","body":"Body1"}`.
- Feature `id` and part `id` are optional in hand-written JSON (a fresh UUID is generated); `suppressed` defaults to `false`.
- Body naming: within a part, the n-th feature whose operation is `newBody` owns `Body<n>`, counted over all such features in order, including suppressed and failed ones, so a failure never renames later bodies.
- Rebuild semantics:
  - Feature statuses: `ok`, `failed(FeatureError)`, `skipped(dependsOn: featureName)`, `suppressed`.
  - A later feature with an already-used name fails with `duplicateName`.
  - Referencing a body whose producing feature failed, was skipped or is suppressed: `skipped(dependsOn:)` naming the root feature.
  - Referencing a body nobody has created yet: `failed(unknownBody)`. Referencing a body used up as a boolean tool: `failed(bodyConsumed)`.
  - A failed join/cut/intersect/boolean/transform leaves the target body as it was.
  - Boolean tools are consumed (removed) on success; multiple tools fold left: `((target op t1) op t2)…`.
  - Cancellation is checked before every feature and before every body's tessellation; a cancelled rebuild throws `CancellationError`.
- Tessellation tolerance in the adapter: 0.05 mm linear deflection.
- Viewport: model point `(x, y, z)` mm Z-up → scene `(x, z, -y) × 0.001` m Y-up, applied once in `ViewportFrame`.

## File Structure

`Packages/CADModel/`:

- `Package.swift`: products `CADModel`, `CADModelKernel`; depends on `../CADKernel`.
- `Sources/CADModel/Scalar.swift`: `Scalar` (number or expression), Codable and literals.
- `Sources/CADModel/Expression.swift`: `ExpressionError`, tokenizer, parser, evaluator.
- `Sources/CADModel/ParameterTable.swift`: `Parameter`, `EvaluatedParameter`, `ParameterTable`.
- `Sources/CADModel/Placement.swift`: `Vector3`, `Placement`, `ResolvedPlacement`.
- `Sources/CADModel/Feature.swift`: `Feature`, `FeatureKind`, `PrimitiveFeature`, `PrimitiveShape`, `BooleanFeature`, `TransformFeature`, `BooleanOperation`, `SolidOperation`.
- `Sources/CADModel/Feature+Codable.swift`: flat `type`-discriminated coding for `FeatureKind` and `SolidOperation`.
- `Sources/CADModel/CADDocument.swift`: `CADDocument`, `Part`, `Assembly`, `DocumentError`, JSON helpers, feature lookup and edit helpers.
- `Sources/CADModel/GeometryKernel.swift`: `GeometryKernel`, `BodyMetrics`, `BodyMesh`.
- `Sources/CADModel/RebuildResult.swift`: `FeatureStatus`, `FeatureError`, `FeatureResult`, `BodyResult`, `PartResult`, `RebuildResult`.
- `Sources/CADModel/PartBuilder.swift`: per-part feature replay.
- `Sources/CADModel/RebuildEngine.swift`: `RebuildEngine`.
- `Sources/CADModelKernel/OCCTGeometryKernel.swift`: the CADKernel adapter.
- Tests: `Tests/CADModelTests/{ScalarTests,ExpressionTests,ParameterTableTests,DocumentCodingTests,DocumentEditingTests,RebuildEngineTests,FakeKernel}.swift`, `Tests/CADModelKernelTests/OCCTGeometryKernelTests.swift`.

App:

- Create `3DModellerApp/Document/CADModelDocument.swift`: `ReferenceFileDocument`, `UTType.cadModel`, `edit(_:undoManager:_:)`.
- Create `3DModellerApp/Viewport/ViewportFrame.swift`: mm/Z-up → m/Y-up, `BodyMesh.meshDescriptor`, scene bounds.
- Create `3DModellerApp/Viewport/ViewportScene.swift`: root entity, grid, light, body entities.
- Create `3DModellerApp/Views/FeatureOutlineView.swift`, `FeatureInspectorView.swift`, `FeatureDisplay.swift` (titles, symbols, property rows, status symbols), `ModelStatisticsView.swift`.
- Modify `ContentView.swift`, `Viewport3DView.swift`, `OrbitCamera.swift`, `ModellerApp.swift`.
- Delete `Scene/*`, `Tools/*`, `Context/SceneContextAdapter.swift`, `Views/PropertiesInspectorView.swift`, `Views/SceneOutlineView.swift`, and tests `AssistantIntegrationTests`, `CreateSolidToolTests`, `SceneDocumentTests`, `SceneManagerTests`, `SolidEntityTests`, `KernelMeshRealityKitTests`.
- Tests: `CADModelDocumentTests`, `ViewportFrameTests`, `FeatureDisplayTests`, extended `OrbitCameraTests`.
- `project.yml`, `Package.swift`, `.github/workflows/ci.yml`, `CLAUDE.md`, `README.md`, `.claude/skills/verify/SKILL.md`.

## Rulings

- **Ruling: one package, two targets.** `CADModel` (pure) and `CADModelKernel` (adapter, depends on CADKernel) live in `Packages/CADModel`. Unit tests in `CADModelTests` only import `CADModel` and run against a fake kernel; `CADModelKernelTests` exercises the real kernel. Cost if wrong: anyone who wants `CADModel` alone still resolves OCCTSwift; splitting the adapter into its own package later is a file move.
- **Ruling: `ReferenceFileDocument` holding a value.** The spec says the document is a value type; the app wraps the `CADDocument` value in a `ReferenceFileDocument` whose `edit` registers the previous value with the window's `UndoManager` under an action name. A plain `FileDocument` binding registers its own unnamed undo step on every write (the problem #9 fixed). Cost if wrong: small; the wrapper is one file.
- **Ruling: ordinal body names.** `Body<n>` is derived from the position of `newBody` features, not stored. Deleting an earlier `newBody` feature renames later bodies. PR 3's delete tool must report or repair that. Cost if wrong: a stored `body` name on `newBody` can be added later as an optional key without breaking files.
- **Ruling: boolean tools are consumed.** Matches Fusion/Onshape defaults and keeps the body list honest. Cost if wrong: add `keepTools` later.
- **Ruling: `assembly` is an empty struct, encoded as `null`.** The key stays visible in every file; PR 9 fills the struct.
- **Ruling: minimal edit UI in PR 2.** The outline's context menu offers Suppress/Unsuppress and Delete so undo/redo through the Edit menu stays exercisable; everything else is read-only until PR 3.

## Review Focus

1. A feature whose field references a parameter that failed (cycle, unknown name, division by zero): the feature fails naming the field and the parameter; unrelated features still build. Pinned in Task 4 (`featureUsingBrokenParameterFails`).
2. Body references that dangle — a body whose producer failed or is suppressed, a body used up as a tool, a body never created: `skipped(dependsOn:)` vs `failed(bodyConsumed/unknownBody)`, never a crash, later independent features still build. Pinned in Task 4.
3. Files that are not ours to read — `format: 2`, `units: "in"`, an unknown feature `type`, a string where an object belongs: opening throws a descriptive error instead of misreading. Pinned in Task 3.
4. Rapid successive edits: an older rebuild must never overwrite a newer one. The engine throws `CancellationError` when cancelled (Task 4 `cancellationStopsTheRebuild`); the app drives it with `.task(id:)` which cancels the previous run (Task 6).
5. An empty or fully suppressed document: zero bodies, no NaN camera, no crash. Pinned in Task 6 (`emptyResultHasNoBounds`, `framingIgnoresMissingBounds`).

---

### Task 1: CADModel package, scalars and expressions

**Files:**

- Create: `Packages/CADModel/Package.swift`
- Create: `Packages/CADModel/Sources/CADModel/Scalar.swift`
- Create: `Packages/CADModel/Sources/CADModel/Expression.swift`
- Create: `Packages/CADModel/Sources/CADModelKernel/OCCTGeometryKernel.swift` (placeholder `import CADModel` only, filled in Task 5)
- Create: `Packages/CADModel/Tests/CADModelTests/ScalarTests.swift`, `ExpressionTests.swift`
- Create: `Packages/CADModel/Tests/CADModelKernelTests/OCCTGeometryKernelTests.swift` (placeholder, filled in Task 5)
- Modify: `.github/workflows/ci.yml` (add `Test CADModel` before `Test app`)

**Interfaces:**

- Produces: `public enum Scalar { case number(Double), expression(String) }` (Codable, literals, `description`); `public enum ExpressionError`; internal `Scalar.evaluate(_ lookup: (String) throws(ExpressionError) -> Double) throws(ExpressionError) -> Double`; internal `Character.isDigit`, `.isIdentifierStart`.

- [ ] **Step 1: Package manifest**

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CADModel",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(name: "CADModel", targets: ["CADModel"]),
        .library(name: "CADModelKernel", targets: ["CADModelKernel"]),
    ],
    dependencies: [
        .package(path: "../CADKernel")
    ],
    targets: [
        .target(name: "CADModel"),
        .target(
            name: "CADModelKernel",
            dependencies: ["CADModel", .product(name: "CADKernel", package: "CADKernel")]
        ),
        .testTarget(name: "CADModelTests", dependencies: ["CADModel"]),
        .testTarget(name: "CADModelKernelTests", dependencies: ["CADModel", "CADModelKernel"]),
    ]
)
```

- [ ] **Step 2: Write the failing tests**

`ScalarTests.swift`:

```swift
import Foundation
import Testing
@testable import CADModel

@Suite("Scalar")
struct ScalarTests {
    private func decode(_ json: String) throws -> Scalar {
        try JSONDecoder().decode(Scalar.self, from: Data(json.utf8))
    }

    @Test("A JSON number decodes as a number and re-encodes as one")
    func number() throws {
        let scalar = try decode("12.5")
        #expect(scalar == .number(12.5))
        #expect(String(decoding: try JSONEncoder().encode(scalar), as: UTF8.self) == "12.5")
    }

    @Test("A JSON string decodes as an expression and re-encodes as a string")
    func expression() throws {
        let scalar = try decode(#""width / 2""#)
        #expect(scalar == .expression("width / 2"))
        #expect(String(decoding: try JSONEncoder().encode(scalar), as: UTF8.self) == #""width \/ 2""#)
    }

    @Test("Anything else is a type mismatch")
    func rejectsOtherTypes() {
        #expect(throws: DecodingError.self) { try decode("true") }
        #expect(throws: DecodingError.self) { try decode("[1]") }
    }

    @Test("Descriptions print whole numbers without a fraction")
    func descriptions() {
        #expect(Scalar.number(10).description == "10")
        #expect(Scalar.number(2.5).description == "2.5")
        #expect(Scalar.expression("a+b").description == "a+b")
    }

    @Test("Literals build scalars")
    func literals() {
        let a: Scalar = 3
        let b: Scalar = 1.5
        let c: Scalar = "t * 2"
        #expect(a == .number(3))
        #expect(b == .number(1.5))
        #expect(c == .expression("t * 2"))
    }
}
```

`ExpressionTests.swift`:

```swift
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

    @Test("Arithmetic follows precedence and parentheses", arguments: [
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

    @Test("Syntax errors are reported", arguments: ["", "1 +", "(1 + 2", "1 2", "2 * * 3", "1.2.3", "3 $ 4", ")", "2e"])
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd Packages/CADModel && xcrun swift test --filter CADModelTests`
Expected: compile failure (`Scalar` not found).

- [ ] **Step 4: Implement**

`Scalar.swift`:

```swift
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
```

`Expression.swift`:

```swift
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
```

Placeholders so the package builds: `Sources/CADModelKernel/OCCTGeometryKernel.swift` contains `import CADModel`; `Tests/CADModelKernelTests/OCCTGeometryKernelTests.swift` contains `import Testing`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd Packages/CADModel && xcrun swift test --filter CADModelTests`
Expected: all Scalar and Expression tests pass.

- [ ] **Step 6: CI step** — in `.github/workflows/ci.yml` insert before `Test app`:

```yaml
- name: Test CADModel
  working-directory: Packages/CADModel
  run: xcrun swift test
```

- [ ] **Step 7: Commit** — `feat(model): evaluate scalar expressions` (package, CI step, tests).

### Task 2: Parameters

**Files:**

- Create: `Packages/CADModel/Sources/CADModel/ParameterTable.swift`
- Test: `Packages/CADModel/Tests/CADModelTests/ParameterTableTests.swift`

**Interfaces:**

- Consumes: `Scalar.evaluate`, `ExpressionError`, `Character.isIdentifierStart/isDigit`.
- Produces: `public struct Parameter { name: String; expression: Scalar }` (Codable); `public struct EvaluatedParameter { name; expression; value: Result<Double, ExpressionError> }`; `public struct ParameterTable { init(_ definitions: [Parameter]); parameters: [EvaluatedParameter]; func value(of name: String) -> Result<Double, ExpressionError>?; func evaluate(_ scalar: Scalar) throws(ExpressionError) -> Double }`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run to verify failure** — `xcrun swift test --filter ParameterTableTests`: compile error.

- [ ] **Step 3: Implement**

```swift
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
        for definition in definitions where expressions.updateValue(definition.expression, forKey: definition.name) != nil {
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
```

- [ ] **Step 4: Run to verify pass** — `xcrun swift test --filter CADModelTests`.
- [ ] **Step 5: Commit** — `feat(model): evaluate document parameters in dependency order`.

### Task 3: Document types and the `.cadmodel` JSON format

**Files:**

- Create: `Sources/CADModel/Placement.swift`, `Feature.swift`, `Feature+Codable.swift`, `CADDocument.swift`
- Test: `Tests/CADModelTests/DocumentCodingTests.swift`, `DocumentEditingTests.swift`

**Interfaces:**

- Consumes: `Scalar`, `Parameter`.
- Produces:
  - `public struct Vector3 { x, y, z: Scalar; init(_ x: Scalar = 0, _ y: Scalar = 0, _ z: Scalar = 0) }`
  - `public struct Placement { translation: Vector3; rotationAxis: Vector3; rotationDegrees: Scalar; static let identity }`
  - `public struct ResolvedPlacement { translation: SIMD3<Double>; rotationAxis: SIMD3<Double>; rotationDegrees: Double }`
  - `public struct Feature: Identifiable { id: UUID; name: String; suppressed: Bool; kind: FeatureKind }`
  - `public enum FeatureKind { case primitive(PrimitiveFeature), boolean(BooleanFeature), transform(TransformFeature) }`
  - `public struct PrimitiveFeature { shape: PrimitiveShape; placement: Placement; operation: SolidOperation; init(_ shape:, placement: = .identity, operation: = .newBody) }`
  - `public enum PrimitiveShape { box(width:depth:height:), cylinder(radius:height:), sphere(radius:), cone(bottomRadius:topRadius:height:), torus(majorRadius:minorRadius:) }`
  - `public struct BooleanFeature { operation: BooleanOperation; target: String; tools: [String] }`, `public struct TransformFeature { body: String; placement: Placement }`
  - `public enum BooleanOperation: String { union, subtract, intersect }`
  - `public enum SolidOperation { newBody, join(String), cut(String), intersect(String); var targetBody: String? }`
  - `public struct Part: Identifiable { id; name; features }`, `public struct Assembly`, `public enum DocumentError { unsupportedFormat(Int), unsupportedUnits(String) }`
  - `public struct CADDocument { parameters; parts; assembly; init(json: Data) throws; func jsonData() throws -> Data; func feature(id:) -> Feature?; mutating func updateFeature(id:_:) -> Bool; mutating func removeFeature(id:) -> Feature? }`

- [ ] **Step 1: Write the failing tests**

`DocumentCodingTests.swift`:

```swift
import Foundation
import Testing
@testable import CADModel

@Suite("Document coding")
struct DocumentCodingTests {
    static let handWritten = """
        {
          "format": 1,
          "units": "mm",
          "parameters": [
            { "name": "width", "expression": 60 },
            { "name": "hole_r", "expression": "width / 12" }
          ],
          "parts": [
            {
              "name": "Plate",
              "features": [
                { "name": "Base", "kind": { "type": "box", "width": "width", "depth": 40, "height": 10 } },
                { "name": "Hole", "kind": {
                    "type": "cylinder", "radius": "hole_r", "height": 10,
                    "placement": { "translation": { "x": 30, "y": 20 } },
                    "operation": { "mode": "cut", "body": "Body1" } } },
                { "name": "Pin", "suppressed": true, "kind": {
                    "type": "cone", "bottomRadius": 2, "topRadius": 1, "height": 5,
                    "placement": { "rotationAxis": { "x": 1 }, "rotationDegrees": 90 } } },
                { "name": "Ring", "kind": { "type": "torus", "majorRadius": 8, "minorRadius": 2 } },
                { "name": "Ball", "kind": { "type": "sphere", "radius": 3 } },
                { "name": "Merge", "kind": { "type": "boolean", "operation": "union", "target": "Body2", "tools": ["Body3"] } },
                { "name": "Lift", "kind": { "type": "transform", "body": "Body2",
                    "placement": { "translation": { "z": "width" } } } }
              ]
            }
          ]
        }
        """

    @Test("A hand-written file decodes with defaults filled in")
    func decodesHandWritten() throws {
        let document = try CADDocument(json: Data(Self.handWritten.utf8))
        #expect(document.parameters == [
            Parameter(name: "width", expression: 60), Parameter(name: "hole_r", expression: "width / 12"),
        ])
        #expect(document.assembly == nil)
        let features = try #require(document.parts.first).features
        #expect(features.map(\.name) == ["Base", "Hole", "Pin", "Ring", "Ball", "Merge", "Lift"])
        #expect(features[0].kind == .primitive(PrimitiveFeature(.box(width: "width", depth: 40, height: 10))))
        #expect(features[0].suppressed == false)
        #expect(features[1].kind == .primitive(PrimitiveFeature(
            .cylinder(radius: "hole_r", height: 10),
            placement: Placement(translation: Vector3(30, 20, 0)),
            operation: .cut("Body1"))))
        #expect(features[2].suppressed)
        #expect(features[2].kind == .primitive(PrimitiveFeature(
            .cone(bottomRadius: 2, topRadius: 1, height: 5),
            placement: Placement(rotationAxis: Vector3(1, 0, 0), rotationDegrees: 90))))
        #expect(features[5].kind == .boolean(BooleanFeature(operation: .union, target: "Body2", tools: ["Body3"])))
        #expect(features[6].kind == .transform(TransformFeature(
            body: "Body2", placement: Placement(translation: Vector3(0, 0, "width")))))
    }

    @Test("Encoding is pretty, key-sorted, reserves the assembly key and round-trips")
    func roundTrip() throws {
        let document = try CADDocument(json: Data(Self.handWritten.utf8))
        let data = try document.jsonData()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\n  \"assembly\" : null,\n  \"format\" : 1,"))
        #expect(text.contains("\"expression\" : \"width / 12\""))
        #expect(try CADDocument(json: data) == document)
        #expect(try document.jsonData() == data)
    }

    @Test("A new document has one empty part")
    func newDocument() throws {
        let document = CADDocument()
        #expect(document.parts.count == 1)
        #expect(document.parts[0].name == "Part1")
        #expect(document.parts[0].features.isEmpty)
        #expect(try CADDocument(json: document.jsonData()) == document)
    }

    @Test("Other formats and units are refused")
    func refusesForeignFiles() {
        #expect(throws: DocumentError.unsupportedFormat(2)) {
            try CADDocument(json: Data(#"{"format": 2, "units": "mm", "parameters": [], "parts": []}"#.utf8))
        }
        #expect(throws: DocumentError.unsupportedUnits("in")) {
            try CADDocument(json: Data(#"{"format": 1, "units": "in", "parameters": [], "parts": []}"#.utf8))
        }
    }

    @Test("Malformed features are decoding errors", arguments: [
        #"{"type": "fillet", "radius": 1}"#,
        #"{"type": "box", "width": 1, "depth": 1}"#,
        #"{"type": "box", "width": 1, "depth": 1, "height": 1, "operation": "cut"}"#,
        #"{"type": "box", "width": 1, "depth": 1, "height": 1, "operation": {"mode": "cut"}}"#,
        #"{"type": "boolean", "operation": "xor", "target": "Body1", "tools": []}"#,
        #"{"type": "sphere", "radius": true}"#,
    ])
    func malformedFeatures(kind: String) {
        let json = #"{"format": 1, "units": "mm", "parts": [{"name": "P", "features": [{"name": "F", "kind": \#(kind)}]}]}"#
        #expect(throws: DecodingError.self) { try CADDocument(json: Data(json.utf8)) }
    }

    @Test("Every solid operation round-trips", arguments: [
        SolidOperation.newBody, .join("Body1"), .cut("Body2"), .intersect("Body3"),
    ])
    func operations(operation: SolidOperation) throws {
        let data = try JSONEncoder().encode(operation)
        #expect(try JSONDecoder().decode(SolidOperation.self, from: data) == operation)
    }
}
```

`DocumentEditingTests.swift`:

```swift
import Foundation
import Testing
@testable import CADModel

@Suite("Document editing")
struct DocumentEditingTests {
    private func document() -> (CADDocument, Feature, Feature) {
        let a = Feature(name: "A", kind: .primitive(PrimitiveFeature(.sphere(radius: 1))))
        let b = Feature(name: "B", kind: .primitive(PrimitiveFeature(.sphere(radius: 2))))
        return (CADDocument(parts: [Part(name: "P1", features: [a]), Part(name: "P2", features: [b])]), a, b)
    }

    @Test("Features are found by id across parts")
    func findsFeatures() {
        let (document, _, b) = document()
        #expect(document.feature(id: b.id) == b)
        #expect(document.feature(id: UUID()) == nil)
    }

    @Test("Updating and removing by id")
    func edits() {
        var (document, a, b) = document()
        #expect(document.updateFeature(id: b.id) { $0.suppressed = true })
        #expect(document.parts[1].features[0].suppressed)
        #expect(!document.updateFeature(id: UUID()) { $0.suppressed = true })
        #expect(document.removeFeature(id: a.id) == a)
        #expect(document.parts[0].features.isEmpty)
        #expect(document.removeFeature(id: a.id) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** — compile errors.

- [ ] **Step 3: Implement**

`Placement.swift`:

```swift
public struct Vector3: Codable, Sendable, Hashable {
    public var x: Scalar
    public var y: Scalar
    public var z: Scalar

    public init(_ x: Scalar = 0, _ y: Scalar = 0, _ z: Scalar = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decodeIfPresent(Scalar.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(Scalar.self, forKey: .y) ?? 0
        z = try container.decodeIfPresent(Scalar.self, forKey: .z) ?? 0
    }
}

public struct Placement: Codable, Sendable, Hashable {
    public var translation: Vector3
    public var rotationAxis: Vector3
    public var rotationDegrees: Scalar

    public static let identity = Placement()

    public init(translation: Vector3 = Vector3(), rotationAxis: Vector3 = Vector3(0, 0, 1), rotationDegrees: Scalar = 0) {
        self.translation = translation
        self.rotationAxis = rotationAxis
        self.rotationDegrees = rotationDegrees
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translation = try container.decodeIfPresent(Vector3.self, forKey: .translation) ?? Vector3()
        rotationAxis = try container.decodeIfPresent(Vector3.self, forKey: .rotationAxis) ?? Vector3(0, 0, 1)
        rotationDegrees = try container.decodeIfPresent(Scalar.self, forKey: .rotationDegrees) ?? 0
    }
}

public struct ResolvedPlacement: Sendable, Hashable {
    public var translation: SIMD3<Double>
    public var rotationAxis: SIMD3<Double>
    public var rotationDegrees: Double

    public init(
        translation: SIMD3<Double> = .zero, rotationAxis: SIMD3<Double> = SIMD3(0, 0, 1), rotationDegrees: Double = 0
    ) {
        self.translation = translation
        self.rotationAxis = rotationAxis
        self.rotationDegrees = rotationDegrees
    }
}
```

`Feature.swift`:

```swift
import Foundation

public struct Feature: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var suppressed: Bool
    public var kind: FeatureKind

    public init(id: UUID = UUID(), name: String, suppressed: Bool = false, kind: FeatureKind) {
        self.id = id
        self.name = name
        self.suppressed = suppressed
        self.kind = kind
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        suppressed = try container.decodeIfPresent(Bool.self, forKey: .suppressed) ?? false
        kind = try container.decode(FeatureKind.self, forKey: .kind)
    }
}

public enum FeatureKind: Sendable, Hashable {
    case primitive(PrimitiveFeature)
    case boolean(BooleanFeature)
    case transform(TransformFeature)
}

public struct PrimitiveFeature: Sendable, Hashable {
    public var shape: PrimitiveShape
    public var placement: Placement
    public var operation: SolidOperation

    public init(_ shape: PrimitiveShape, placement: Placement = .identity, operation: SolidOperation = .newBody) {
        self.shape = shape
        self.placement = placement
        self.operation = operation
    }
}

public enum PrimitiveShape: Sendable, Hashable {
    case box(width: Scalar, depth: Scalar, height: Scalar)
    case cylinder(radius: Scalar, height: Scalar)
    case sphere(radius: Scalar)
    case cone(bottomRadius: Scalar, topRadius: Scalar, height: Scalar)
    case torus(majorRadius: Scalar, minorRadius: Scalar)
}

public struct BooleanFeature: Sendable, Hashable {
    public var operation: BooleanOperation
    public var target: String
    public var tools: [String]

    public init(operation: BooleanOperation, target: String, tools: [String]) {
        self.operation = operation
        self.target = target
        self.tools = tools
    }
}

public struct TransformFeature: Sendable, Hashable {
    public var body: String
    public var placement: Placement

    public init(body: String, placement: Placement) {
        self.body = body
        self.placement = placement
    }
}

public enum BooleanOperation: String, Codable, Sendable, Hashable, CaseIterable {
    case union, subtract, intersect
}

public enum SolidOperation: Sendable, Hashable {
    case newBody
    case join(String)
    case cut(String)
    case intersect(String)

    public var targetBody: String? {
        switch self {
        case .newBody: nil
        case .join(let body), .cut(let body), .intersect(let body): body
        }
    }

    var booleanOperation: BooleanOperation? {
        switch self {
        case .newBody: nil
        case .join: .union
        case .cut: .subtract
        case .intersect: .intersect
        }
    }
}

extension FeatureKind {
    var createsNewBody: Bool {
        if case .primitive(let primitive) = self { primitive.operation == .newBody } else { false }
    }

    func affectedBody(newBody: String?) -> String? {
        switch self {
        case .primitive(let primitive): primitive.operation.targetBody ?? newBody
        case .boolean(let boolean): boolean.target
        case .transform(let transform): transform.body
        }
    }
}
```

`Feature+Codable.swift`:

```swift
extension FeatureKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, width, depth, height, radius, bottomRadius, topRadius, majorRadius, minorRadius
        case placement, operation, target, tools, body
    }

    private enum KindName: String, Codable {
        case box, cylinder, sphere, cone, torus, boolean, transform
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func scalar(_ key: CodingKeys) throws -> Scalar { try container.decode(Scalar.self, forKey: key) }
        let shape: PrimitiveShape
        switch try container.decode(KindName.self, forKey: .type) {
        case .boolean:
            self = .boolean(
                BooleanFeature(
                    operation: try container.decode(BooleanOperation.self, forKey: .operation),
                    target: try container.decode(String.self, forKey: .target),
                    tools: try container.decode([String].self, forKey: .tools)
                ))
            return
        case .transform:
            self = .transform(
                TransformFeature(
                    body: try container.decode(String.self, forKey: .body),
                    placement: try container.decodeIfPresent(Placement.self, forKey: .placement) ?? .identity
                ))
            return
        case .box:
            shape = .box(width: try scalar(.width), depth: try scalar(.depth), height: try scalar(.height))
        case .cylinder:
            shape = .cylinder(radius: try scalar(.radius), height: try scalar(.height))
        case .sphere:
            shape = .sphere(radius: try scalar(.radius))
        case .cone:
            shape = .cone(
                bottomRadius: try scalar(.bottomRadius), topRadius: try scalar(.topRadius), height: try scalar(.height))
        case .torus:
            shape = .torus(majorRadius: try scalar(.majorRadius), minorRadius: try scalar(.minorRadius))
        }
        self = .primitive(
            PrimitiveFeature(
                shape,
                placement: try container.decodeIfPresent(Placement.self, forKey: .placement) ?? .identity,
                operation: try container.decodeIfPresent(SolidOperation.self, forKey: .operation) ?? .newBody
            ))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .boolean(let boolean):
            try container.encode(KindName.boolean, forKey: .type)
            try container.encode(boolean.operation, forKey: .operation)
            try container.encode(boolean.target, forKey: .target)
            try container.encode(boolean.tools, forKey: .tools)
        case .transform(let transform):
            try container.encode(KindName.transform, forKey: .type)
            try container.encode(transform.body, forKey: .body)
            try container.encode(transform.placement, forKey: .placement)
        case .primitive(let primitive):
            try container.encode(primitive.placement, forKey: .placement)
            try container.encode(primitive.operation, forKey: .operation)
            switch primitive.shape {
            case .box(let width, let depth, let height):
                try container.encode(KindName.box, forKey: .type)
                try container.encode(width, forKey: .width)
                try container.encode(depth, forKey: .depth)
                try container.encode(height, forKey: .height)
            case .cylinder(let radius, let height):
                try container.encode(KindName.cylinder, forKey: .type)
                try container.encode(radius, forKey: .radius)
                try container.encode(height, forKey: .height)
            case .sphere(let radius):
                try container.encode(KindName.sphere, forKey: .type)
                try container.encode(radius, forKey: .radius)
            case .cone(let bottomRadius, let topRadius, let height):
                try container.encode(KindName.cone, forKey: .type)
                try container.encode(bottomRadius, forKey: .bottomRadius)
                try container.encode(topRadius, forKey: .topRadius)
                try container.encode(height, forKey: .height)
            case .torus(let majorRadius, let minorRadius):
                try container.encode(KindName.torus, forKey: .type)
                try container.encode(majorRadius, forKey: .majorRadius)
                try container.encode(minorRadius, forKey: .minorRadius)
            }
        }
    }
}

extension SolidOperation: Codable {
    private enum CodingKeys: String, CodingKey { case mode, body }
    private enum Mode: String, Codable { case newBody, join, cut, intersect }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(Mode.self, forKey: .mode)
        if mode == .newBody {
            self = .newBody
            return
        }
        let body = try container.decode(String.self, forKey: .body)
        self = switch mode {
        case .newBody: .newBody
        case .join: .join(body)
        case .cut: .cut(body)
        case .intersect: .intersect(body)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let mode: Mode = switch self {
        case .newBody: .newBody
        case .join: .join
        case .cut: .cut
        case .intersect: .intersect
        }
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(targetBody, forKey: .body)
    }
}
```

`CADDocument.swift`:

```swift
import Foundation

public struct Part: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var features: [Feature]

    public init(id: UUID = UUID(), name: String, features: [Feature] = []) {
        self.id = id
        self.name = name
        self.features = features
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        features = try container.decodeIfPresent([Feature].self, forKey: .features) ?? []
    }
}

public struct Assembly: Codable, Sendable, Hashable {
    public init() {}
}

public enum DocumentError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case unsupportedFormat(Int)
    case unsupportedUnits(String)

    public var description: String {
        switch self {
        case .unsupportedFormat(let format): "Unsupported document format \(format); this app reads format \(CADDocument.format)"
        case .unsupportedUnits(let units): "Unsupported units '\(units)'; documents use \(CADDocument.units)"
        }
    }

    public var errorDescription: String? { description }
}

public struct CADDocument: Codable, Sendable, Hashable {
    public static let format = 1
    public static let units = "mm"

    public var parameters: [Parameter]
    public var parts: [Part]
    public var assembly: Assembly?

    public init(parameters: [Parameter] = [], parts: [Part] = [Part(name: "Part1")], assembly: Assembly? = nil) {
        self.parameters = parameters
        self.parts = parts
        self.assembly = assembly
    }

    private enum CodingKeys: String, CodingKey { case format, units, parameters, parts, assembly }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = try container.decode(Int.self, forKey: .format)
        guard format == Self.format else { throw DocumentError.unsupportedFormat(format) }
        let units = try container.decode(String.self, forKey: .units)
        guard units == Self.units else { throw DocumentError.unsupportedUnits(units) }
        parameters = try container.decodeIfPresent([Parameter].self, forKey: .parameters) ?? []
        parts = try container.decodeIfPresent([Part].self, forKey: .parts) ?? []
        assembly = try container.decodeIfPresent(Assembly.self, forKey: .assembly)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.format, forKey: .format)
        try container.encode(Self.units, forKey: .units)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(parts, forKey: .parts)
        try container.encode(assembly, forKey: .assembly)
    }
}

extension CADDocument {
    public init(json: Data) throws {
        self = try JSONDecoder().decode(CADDocument.self, from: json)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func feature(id: UUID) -> Feature? {
        parts.lazy.flatMap(\.features).first { $0.id == id }
    }

    @discardableResult
    public mutating func updateFeature(id: UUID, _ change: (inout Feature) -> Void) -> Bool {
        for part in parts.indices {
            if let index = parts[part].features.firstIndex(where: { $0.id == id }) {
                change(&parts[part].features[index])
                return true
            }
        }
        return false
    }

    @discardableResult
    public mutating func removeFeature(id: UUID) -> Feature? {
        for part in parts.indices {
            if let index = parts[part].features.firstIndex(where: { $0.id == id }) {
                return parts[part].features.remove(at: index)
            }
        }
        return nil
    }
}
```



- [ ] **Step 4: Run to verify pass** — `xcrun swift test --filter CADModelTests`.
- [ ] **Step 5: Commit** — `feat(model): read and write the cadmodel document format`.

### Task 4: Geometry kernel protocol and rebuild engine

**Files:**

- Create: `Sources/CADModel/GeometryKernel.swift`, `RebuildResult.swift`, `PartBuilder.swift`, `RebuildEngine.swift`
- Test: `Tests/CADModelTests/FakeKernel.swift`, `RebuildEngineTests.swift`

**Interfaces:**

- Consumes: document types, `ParameterTable`.
- Produces:

```swift
public protocol GeometryKernel: Sendable {
    associatedtype Body: Sendable
    func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement) throws -> Body
    func cylinder(radius: Double, height: Double, placement: ResolvedPlacement) throws -> Body
    func sphere(radius: Double, placement: ResolvedPlacement) throws -> Body
    func cone(bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement) throws -> Body
    func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement) throws -> Body
    func boolean(_ operation: BooleanOperation, _ target: Body, _ tool: Body) throws -> Body
    func transform(_ body: Body, by placement: ResolvedPlacement) throws -> Body
    func metrics(of body: Body) throws -> BodyMetrics
    func mesh(of body: Body) throws -> BodyMesh
}
public struct BodyMetrics { volume: Double?; boundsMin, boundsMax: SIMD3<Double>; faceCount, solidCount: Int; isValid, isClosed: Bool }
public struct BodyMesh { positions: [SIMD3<Float>]; normals: [SIMD3<Float>]; indices: [UInt32]; var triangleCount: Int }
public enum FeatureStatus { ok, failed(FeatureError), skipped(dependsOn: String), suppressed }  // CustomStringConvertible
public enum FeatureError { expression(field: String, ExpressionError), duplicateName(String), unknownBody(String), bodyConsumed(String, by: String), invalidTools(String), kernel(String) }
public struct FeatureResult { id: UUID; name: String; status: FeatureStatus; body: String? }
public struct BodyResult { name: String; metrics: BodyMetrics?; mesh: BodyMesh?; error: String? }
public struct PartResult { id: UUID; name: String; features: [FeatureResult]; bodies: [BodyResult] }
public struct RebuildResult { parameters: ParameterTable; parts: [PartResult]; bodies; triangleCount; failedFeatureCount; func feature(id:) -> FeatureResult? }
public struct RebuildEngine<Kernel: GeometryKernel> { init(kernel:); @concurrent func rebuild(_ document: CADDocument) async throws -> RebuildResult }
```

- [ ] **Step 1: Fake kernel** (`FakeKernel.swift`)

```swift
import CADModel
import Foundation
import Synchronization

struct FakeBody: Sendable, Equatable {
    var volume: Double
}

struct FakeKernelError: Error, CustomStringConvertible {
    let description: String
}

final class FakeKernel: GeometryKernel {
    private let log = Mutex<[String]>([])
    private let mainThreadCalls = Mutex(0)
    let onCall: @Sendable (String) -> Void

    init(onCall: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onCall = onCall
    }

    var calls: [String] { log.withLock { $0 } }
    var callsOnMainThread: Int { mainThreadCalls.withLock { $0 } }

    private func record(_ call: String) {
        log.withLock { $0.append(call) }
        if Thread.isMainThread { mainThreadCalls.withLock { $0 += 1 } }
        onCall(call)
    }

    private static func text(_ p: ResolvedPlacement) -> String {
        let t = p.translation
        let a = p.rotationAxis
        return "@(\(Scalar.number(t.x)),\(Scalar.number(t.y)),\(Scalar.number(t.z)))"
            + " \(Scalar.number(p.rotationDegrees))°(\(Scalar.number(a.x)),\(Scalar.number(a.y)),\(Scalar.number(a.z)))"
    }

    private static func requirePositive(_ values: Double...) throws {
        guard values.allSatisfy({ $0 > 0 }) else { throw FakeKernelError(description: "dimensions must be positive") }
    }

    func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody {
        record("box \(Scalar.number(width))x\(Scalar.number(depth))x\(Scalar.number(height)) \(Self.text(placement))")
        try Self.requirePositive(width, depth, height)
        return FakeBody(volume: width * depth * height)
    }

    func cylinder(radius: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody {
        record("cylinder r\(Scalar.number(radius)) h\(Scalar.number(height)) \(Self.text(placement))")
        try Self.requirePositive(radius, height)
        return FakeBody(volume: 100 * radius * radius * height)
    }

    func sphere(radius: Double, placement: ResolvedPlacement) throws -> FakeBody {
        record("sphere r\(Scalar.number(radius))")
        try Self.requirePositive(radius)
        return FakeBody(volume: 1000 * radius)
    }

    func cone(bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody {
        record("cone")
        guard bottomRadius != topRadius else { throw FakeKernelError(description: "cone radii must differ") }
        return FakeBody(volume: height)
    }

    func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement) throws -> FakeBody {
        record("torus")
        return FakeBody(volume: majorRadius * minorRadius)
    }

    func boolean(_ operation: BooleanOperation, _ target: FakeBody, _ tool: FakeBody) throws -> FakeBody {
        record("\(operation.rawValue) \(Scalar.number(target.volume)) \(Scalar.number(tool.volume))")
        let volume = switch operation {
        case .union: target.volume + tool.volume
        case .subtract: target.volume - tool.volume
        case .intersect: min(target.volume, tool.volume)
        }
        guard volume > 0 else { throw FakeKernelError(description: "The operation left no solid") }
        return FakeBody(volume: volume)
    }

    func transform(_ body: FakeBody, by placement: ResolvedPlacement) throws -> FakeBody {
        record("transform \(Scalar.number(body.volume)) \(Self.text(placement))")
        return body
    }

    func metrics(of body: FakeBody) throws -> BodyMetrics {
        BodyMetrics(
            volume: body.volume, boundsMin: .zero, boundsMax: SIMD3(1, 1, 1),
            faceCount: 6, solidCount: 1, isValid: true, isClosed: true)
    }

    func mesh(of body: FakeBody) throws -> BodyMesh {
        BodyMesh(positions: [.zero, SIMD3(1, 0, 0), SIMD3(0, 1, 0)], normals: Array(repeating: SIMD3(0, 0, 1), count: 3), indices: [0, 1, 2])
    }
}
```

- [ ] **Step 2: Write the failing tests** (`RebuildEngineTests.swift`)

```swift
import Foundation
import Testing
@testable import CADModel

@Suite("Rebuild engine")
struct RebuildEngineTests {
    let kernel = FakeKernel()
    var engine: RebuildEngine<FakeKernel> { RebuildEngine(kernel: kernel) }

    private func box(_ name: String, _ w: Scalar = 10, _ d: Scalar = 10, _ h: Scalar = 10,
                     placement: Placement = .identity, operation: SolidOperation = .newBody, suppressed: Bool = false) -> Feature {
        Feature(name: name, suppressed: suppressed,
                kind: .primitive(PrimitiveFeature(.box(width: w, depth: d, height: h), placement: placement, operation: operation)))
    }

    private func rebuild(_ features: [Feature], parameters: [Parameter] = []) async throws -> PartResult {
        let result = try await engine.rebuild(CADDocument(parameters: parameters, parts: [Part(name: "P", features: features)]))
        return try #require(result.parts.first)
    }

    @Test("Primitives become numbered bodies with evaluated dimensions and degree placements")
    func primitives() async throws {
        let part = try await rebuild(
            [
                box("A", "w", 2, 3, placement: Placement(translation: Vector3(1, "w", 0), rotationDegrees: 90)),
                Feature(name: "B", kind: .primitive(PrimitiveFeature(.cylinder(radius: 1, height: "w * 2")))),
            ],
            parameters: [Parameter(name: "w", expression: 5)])
        #expect(part.features.map(\.status) == [.ok, .ok])
        #expect(part.features.map(\.body) == ["Body1", "Body2"])
        #expect(part.bodies.map(\.name) == ["Body1", "Body2"])
        #expect(part.bodies[0].metrics?.volume == 30)
        #expect(part.bodies[0].mesh?.triangleCount == 1)
        #expect(kernel.calls.first == "box 5x2x3 @(1,5,0) 90°(0,0,1)")
        #expect(kernel.calls[1] == "cylinder r1 h10 @(0,0,0) 0°(0,0,1)")
    }

    @Test("Cut, join and intersect modify the named body in place")
    func operations() async throws {
        let part = try await rebuild([
            box("A", 10, 10, 10),
            box("B", 1, 1, 1, operation: .cut("Body1")),
            box("C", 2, 1, 1, operation: .join("Body1")),
            box("D", 3, 1, 1, operation: .intersect("Body1")),
        ])
        #expect(part.features.map(\.status) == [.ok, .ok, .ok, .ok])
        #expect(part.features.map(\.body) == ["Body1", "Body1", "Body1", "Body1"])
        #expect(part.bodies.map(\.name) == ["Body1"])
        #expect(part.bodies[0].metrics?.volume == 3)
    }

    @Test("A boolean folds its tools into the target and consumes them")
    func booleanFolds() async throws {
        let part = try await rebuild([
            box("A", 10, 10, 10), box("B", 1, 1, 1), box("C", 2, 1, 1),
            Feature(name: "Cut", kind: .boolean(BooleanFeature(operation: .subtract, target: "Body1", tools: ["Body2", "Body3"]))),
            Feature(name: "Again", kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: ["Body2"]))),
        ])
        #expect(kernel.calls.suffix(2) == ["subtract 1000 1", "subtract 999 2"])
        #expect(part.bodies.map(\.name) == ["Body1"])
        #expect(part.bodies[0].metrics?.volume == 997)
        #expect(part.features[4].status == .failed(.bodyConsumed("Body2", by: "Cut")))
    }

    @Test("Booleans with no tools, the target as a tool, or repeated tools fail", arguments: [
        [String](), ["Body1"], ["Body2", "Body2"],
    ])
    func invalidTools(tools: [String]) async throws {
        let part = try await rebuild([
            box("A"), box("B"),
            Feature(name: "X", kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: tools))),
        ])
        guard case .failed(.invalidTools) = part.features[2].status else {
            Issue.record("expected invalidTools, got \(part.features[2].status)")
            return
        }
        #expect(part.bodies.count == 2)
    }

    @Test("Transforms move a body")
    func transform() async throws {
        let part = try await rebuild([
            box("A"),
            Feature(name: "Move", kind: .transform(TransformFeature(
                body: "Body1", placement: Placement(translation: Vector3(0, 0, 5), rotationAxis: Vector3(1, 0, 0), rotationDegrees: 45)))),
        ])
        #expect(part.features[1].status == .ok)
        #expect(kernel.calls.last == "transform 1000 @(0,0,5) 45°(1,0,0)")
    }

    @Test("A kernel failure fails only that feature and leaves the body untouched")
    func kernelFailure() async throws {
        let part = try await rebuild([
            box("A", 10, 10, 10),
            box("Bad", 0, 1, 1, operation: .cut("Body1")),
            box("After", 1, 1, 1, operation: .cut("Body1")),
        ])
        #expect(part.features[1].status == .failed(.kernel("dimensions must be positive")))
        #expect(part.features[2].status == .ok)
        #expect(part.bodies[0].metrics?.volume == 999)
    }

    @Test("Dependents of a failed or suppressed body are skipped; unrelated features still build")
    func skipping() async throws {
        let part = try await rebuild([
            box("Broken", -1),
            box("Hidden", suppressed: true),
            box("UsesBroken", operation: .join("Body1")),
            box("UsesHidden", operation: .cut("Body2")),
            Feature(name: "Chain", kind: .boolean(BooleanFeature(operation: .union, target: "Body5", tools: ["Body1"]))),
            box("Fine"),
        ])
        #expect(part.features.map(\.status) == [
            .failed(.kernel("dimensions must be positive")),
            .suppressed,
            .skipped(dependsOn: "Broken"),
            .skipped(dependsOn: "Hidden"),
            .failed(.unknownBody("Body5")),
            .ok,
        ])
        #expect(part.features.map(\.body) == ["Body1", "Body2", "Body1", "Body2", "Body5", "Body3"])
        #expect(part.bodies.map(\.name) == ["Body3"])
    }

    @Test("A body that no feature has created yet is unknown")
    func unknownBody() async throws {
        let part = try await rebuild([box("A", operation: .cut("Body7")), box("B")])
        #expect(part.features[0].status == .failed(.unknownBody("Body7")))
        #expect(part.features[1].status == .ok)
    }

    @Test("A skipped new-body feature passes its root cause on")
    func skippedChain() async throws {
        let part = try await rebuild([
            box("Root", 0),
            Feature(name: "Grow", kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: ["Body1x"]))),
            box("Mid", operation: .cut("Body1")),
        ])
        #expect(part.features[2].status == .skipped(dependsOn: "Root"))
    }

    @Test("A duplicate feature name fails the later feature and still reserves its body number")
    func duplicateNames() async throws {
        let part = try await rebuild([box("A"), box("A"), box("B")])
        #expect(part.features.map(\.status) == [.ok, .failed(.duplicateName("A")), .ok])
        #expect(part.bodies.map(\.name) == ["Body1", "Body3"])
    }

    @Test("A feature using a broken parameter fails naming the field")
    func featureUsingBrokenParameterFails() async throws {
        let part = try await rebuild(
            [box("A", "loop"), box("B", 1, 1, "1/0"), box("C", "nope"), box("D", "ok")],
            parameters: [
                Parameter(name: "loop", expression: "loop + 1"), Parameter(name: "ok", expression: 2),
            ])
        #expect(part.features.map(\.status) == [
            .failed(.expression(field: "width", .failedParameter("loop"))),
            .failed(.expression(field: "height", .divisionByZero)),
            .failed(.expression(field: "width", .unknownName("nope"))),
            .ok,
        ])
    }

    @Test("Placement fields are named in expression errors")
    func placementErrors() async throws {
        let part = try await rebuild([box("A", placement: Placement(rotationDegrees: "x"))])
        #expect(part.features[0].status == .failed(.expression(field: "placement.rotationDegrees", .unknownName("x"))))
    }

    @Test("Parts rebuild independently with their own body names")
    func parts() async throws {
        let result = try await engine.rebuild(CADDocument(parts: [
            Part(name: "P1", features: [box("A")]), Part(name: "P2", features: [box("A"), box("B")]),
        ]))
        #expect(result.parts.map { $0.bodies.map(\.name) } == [["Body1"], ["Body1", "Body2"]])
        #expect(result.bodies.count == 3)
        #expect(result.triangleCount == 3)
        #expect(result.failedFeatureCount == 0)
    }

    @Test("The result exposes evaluated parameters and features by id")
    func lookups() async throws {
        let feature = box("A", 0)
        let result = try await engine.rebuild(CADDocument(
            parameters: [Parameter(name: "w", expression: "3 * 4")], parts: [Part(name: "P", features: [feature])]))
        #expect(result.parameters.value(of: "w") == .success(12))
        #expect(result.feature(id: feature.id)?.name == "A")
        #expect(result.failedFeatureCount == 1)
    }

    @Test("Rebuild runs off the main thread")
    @MainActor
    func offMain() async throws {
        _ = try await engine.rebuild(CADDocument(parts: [Part(name: "P", features: [box("A")])]))
        #expect(kernel.calls.count == 1)
        #expect(kernel.callsOnMainThread == 0)
    }

    @Test("Cancellation stops the rebuild between features")
    func cancellationStopsTheRebuild() async throws {
        let kernel = FakeKernel { _ in withUnsafeCurrentTask { $0?.cancel() } }
        let document = CADDocument(parts: [Part(name: "P", features: [box("A"), box("B")])])
        await #expect(throws: CancellationError.self) {
            try await RebuildEngine(kernel: kernel).rebuild(document)
        }
        #expect(kernel.calls.count == 1)
    }

    @Test("Statuses describe themselves for listings")
    func statusDescriptions() {
        #expect(FeatureStatus.ok.description == "ok")
        #expect(FeatureStatus.suppressed.description == "suppressed")
        #expect(FeatureStatus.skipped(dependsOn: "Box1").description == "skipped: depends on Box1")
        #expect(FeatureStatus.failed(.expression(field: "width", .unknownName("w"))).description
            == "failed: width: unknown parameter 'w'")
        #expect(FeatureStatus.failed(.bodyConsumed("Body2", by: "Cut1")).description
            == "failed: Body2 was used up as a tool by Cut1")
    }
}
```

`Chain` is a boolean, so it creates no body; `Body5` is never created and is unknown. In `skippedChain`, `Grow` targets `Body1` (broken by `Root`) and is skipped before its tool is checked, so `Mid` is `skipped(Root)` too.

- [ ] **Step 3: Run to verify failure** — compile errors.

- [ ] **Step 4: Implement**

`GeometryKernel.swift`:

```swift
public protocol GeometryKernel: Sendable {
    associatedtype Body: Sendable

    func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement) throws -> Body
    func cylinder(radius: Double, height: Double, placement: ResolvedPlacement) throws -> Body
    func sphere(radius: Double, placement: ResolvedPlacement) throws -> Body
    func cone(bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement) throws -> Body
    func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement) throws -> Body
    func boolean(_ operation: BooleanOperation, _ target: Body, _ tool: Body) throws -> Body
    func transform(_ body: Body, by placement: ResolvedPlacement) throws -> Body
    func metrics(of body: Body) throws -> BodyMetrics
    func mesh(of body: Body) throws -> BodyMesh
}

public struct BodyMetrics: Sendable, Equatable {
    public var volume: Double?
    public var boundsMin: SIMD3<Double>
    public var boundsMax: SIMD3<Double>
    public var faceCount: Int
    public var solidCount: Int
    public var isValid: Bool
    public var isClosed: Bool

    public init(
        volume: Double?, boundsMin: SIMD3<Double>, boundsMax: SIMD3<Double>, faceCount: Int, solidCount: Int,
        isValid: Bool, isClosed: Bool
    ) { … assign all … }
}

public struct BodyMesh: Sendable, Equatable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var indices: [UInt32]

    public init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) { … }

    public var triangleCount: Int { indices.count / 3 }
}
```

`RebuildResult.swift`:

```swift
import Foundation

public enum FeatureStatus: Sendable, Equatable, CustomStringConvertible {
    case ok
    case failed(FeatureError)
    case skipped(dependsOn: String)
    case suppressed

    public var description: String {
        switch self {
        case .ok: "ok"
        case .failed(let error): "failed: \(error)"
        case .skipped(let dependency): "skipped: depends on \(dependency)"
        case .suppressed: "suppressed"
        }
    }
}

public enum FeatureError: Error, Sendable, Equatable, CustomStringConvertible {
    case expression(field: String, ExpressionError)
    case duplicateName(String)
    case unknownBody(String)
    case bodyConsumed(String, by: String)
    case invalidTools(String)
    case kernel(String)

    public var description: String {
        switch self {
        case .expression(let field, let error): "\(field): \(error)"
        case .duplicateName(let name): "another feature in this part is already named '\(name)'"
        case .unknownBody(let name): "no body named '\(name)' exists at this point"
        case .bodyConsumed(let name, let feature): "\(name) was used up as a tool by \(feature)"
        case .invalidTools(let detail): detail
        case .kernel(let detail): detail
        }
    }
}

public struct FeatureResult: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let status: FeatureStatus
    public let body: String?
}

public struct BodyResult: Sendable, Equatable {
    public let name: String
    public let metrics: BodyMetrics?
    public let mesh: BodyMesh?
    public let error: String?
}

public struct PartResult: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let features: [FeatureResult]
    public let bodies: [BodyResult]
}

public struct RebuildResult: Sendable, Equatable {
    public let parameters: ParameterTable
    public let parts: [PartResult]

    public var bodies: [BodyResult] { parts.flatMap(\.bodies) }
    public var triangleCount: Int { bodies.reduce(0) { $0 + ($1.mesh?.triangleCount ?? 0) } }
    public var failedFeatureCount: Int {
        parts.flatMap(\.features).count { if case .failed = $0.status { true } else { false } }
    }

    public func feature(id: UUID) -> FeatureResult? {
        parts.lazy.flatMap(\.features).first { $0.id == id }
    }
}
```

`PartBuilder.swift`:

```swift
struct PartBuilder<Kernel: GeometryKernel> {
    private enum Unavailable {
        case brokenBy(String)
        case consumedBy(String)
    }

    private enum Stop: Error {
        case failed(FeatureError)
        case skipped(dependsOn: String)
    }

    let kernel: Kernel
    let parameters: ParameterTable
    private var bodies: [(name: String, body: Kernel.Body)] = []
    private var unavailable: [String: Unavailable] = [:]
    private var names: Set<String> = []
    private var newBodyCount = 0

    init(kernel: Kernel, parameters: ParameterTable) {
        self.kernel = kernel
        self.parameters = parameters
    }

    mutating func apply(_ feature: Feature) -> FeatureResult {
        var newBody: String?
        if feature.kind.createsNewBody {
            newBodyCount += 1
            newBody = "Body\(newBodyCount)"
        }
        let status: FeatureStatus
        if !names.insert(feature.name).inserted {
            status = .failed(.duplicateName(feature.name))
        } else if feature.suppressed {
            status = .suppressed
        } else {
            do throws(Stop) {
                try build(feature, newBody: newBody)
                status = .ok
            } catch {
                switch error {
                case .failed(let error): status = .failed(error)
                case .skipped(let dependency): status = .skipped(dependsOn: dependency)
                }
            }
        }
        if let newBody, status != .ok {
            if case .skipped(let root) = status {
                unavailable[newBody] = .brokenBy(root)
            } else {
                unavailable[newBody] = .brokenBy(feature.name)
            }
        }
        return FeatureResult(id: feature.id, name: feature.name, status: status, body: feature.kind.affectedBody(newBody: newBody))
    }

    func bodyResults() throws -> [BodyResult] {
        var results: [BodyResult] = []
        for (name, body) in bodies {
            try Task.checkCancellation()
            var problems: [String] = []
            let metrics: BodyMetrics?
            do { metrics = try kernel.metrics(of: body) } catch {
                metrics = nil
                problems.append(String(describing: error))
            }
            let mesh: BodyMesh?
            do { mesh = try kernel.mesh(of: body) } catch {
                mesh = nil
                problems.append(String(describing: error))
            }
            results.append(BodyResult(
                name: name, metrics: metrics, mesh: mesh, error: problems.isEmpty ? nil : problems.joined(separator: "; ")))
        }
        return results
    }

    private mutating func build(_ feature: Feature, newBody: String?) throws(Stop) {
        switch feature.kind {
        case .primitive(let primitive):
            var target: Kernel.Body?
            if let name = primitive.operation.targetBody { target = try body(named: name) }
            let solid = try make(primitive.shape, primitive.placement)
            if let name = primitive.operation.targetBody, let target, let operation = primitive.operation.booleanOperation {
                let combined = try kernelCall { try kernel.boolean(operation, target, solid) }
                store(combined, as: name)
            } else if let newBody {
                store(solid, as: newBody)
            }
        case .boolean(let boolean):
            guard !boolean.tools.isEmpty else { throw .failed(.invalidTools("a boolean needs at least one tool body")) }
            guard !boolean.tools.contains(boolean.target) else {
                throw .failed(.invalidTools("\(boolean.target) cannot be a tool of itself"))
            }
            guard Set(boolean.tools).count == boolean.tools.count else {
                throw .failed(.invalidTools("a tool body is listed more than once"))
            }
            var result = try body(named: boolean.target)
            var tools: [Kernel.Body] = []
            for name in boolean.tools { tools.append(try body(named: name)) }
            for tool in tools {
                let current = result
                result = try kernelCall { try kernel.boolean(boolean.operation, current, tool) }
            }
            store(result, as: boolean.target)
            for name in boolean.tools {
                bodies.removeAll { $0.name == name }
                unavailable[name] = .consumedBy(feature.name)
            }
        case .transform(let transform):
            let original = try body(named: transform.body)
            let placement = try resolve(transform.placement)
            store(try kernelCall { try kernel.transform(original, by: placement) }, as: transform.body)
        }
    }

    private func body(named name: String) throws(Stop) -> Kernel.Body {
        if let entry = bodies.first(where: { $0.name == name }) { return entry.body }
        switch unavailable[name] {
        case .brokenBy(let feature)?: throw .skipped(dependsOn: feature)
        case .consumedBy(let feature)?: throw .failed(.bodyConsumed(name, by: feature))
        case nil: throw .failed(.unknownBody(name))
        }
    }

    private mutating func store(_ body: Kernel.Body, as name: String) {
        if let index = bodies.firstIndex(where: { $0.name == name }) {
            bodies[index].body = body
        } else {
            bodies.append((name, body))
        }
    }

    private func make(_ shape: PrimitiveShape, _ placement: Placement) throws(Stop) -> Kernel.Body {
        switch shape {
        case .box(let width, let depth, let height):
            let (w, d, h) = (try value(width, "width"), try value(depth, "depth"), try value(height, "height"))
            let p = try resolve(placement)
            return try kernelCall { try kernel.box(width: w, depth: d, height: h, placement: p) }
        case .cylinder(let radius, let height):
            let (r, h) = (try value(radius, "radius"), try value(height, "height"))
            let p = try resolve(placement)
            return try kernelCall { try kernel.cylinder(radius: r, height: h, placement: p) }
        case .sphere(let radius):
            let r = try value(radius, "radius")
            let p = try resolve(placement)
            return try kernelCall { try kernel.sphere(radius: r, placement: p) }
        case .cone(let bottomRadius, let topRadius, let height):
            let (b, t, h) = (
                try value(bottomRadius, "bottomRadius"), try value(topRadius, "topRadius"), try value(height, "height")
            )
            let p = try resolve(placement)
            return try kernelCall { try kernel.cone(bottomRadius: b, topRadius: t, height: h, placement: p) }
        case .torus(let majorRadius, let minorRadius):
            let (major, minor) = (try value(majorRadius, "majorRadius"), try value(minorRadius, "minorRadius"))
            let p = try resolve(placement)
            return try kernelCall { try kernel.torus(majorRadius: major, minorRadius: minor, placement: p) }
        }
    }

    private func resolve(_ placement: Placement) throws(Stop) -> ResolvedPlacement {
        ResolvedPlacement(
            translation: try vector(placement.translation, "placement.translation"),
            rotationAxis: try vector(placement.rotationAxis, "placement.rotationAxis"),
            rotationDegrees: try value(placement.rotationDegrees, "placement.rotationDegrees")
        )
    }

    private func vector(_ vector: Vector3, _ field: String) throws(Stop) -> SIMD3<Double> {
        SIMD3(try value(vector.x, "\(field).x"), try value(vector.y, "\(field).y"), try value(vector.z, "\(field).z"))
    }

    private func value(_ scalar: Scalar, _ field: String) throws(Stop) -> Double {
        do {
            return try parameters.evaluate(scalar)
        } catch {
            throw .failed(.expression(field: field, error))
        }
    }

    private func kernelCall<T>(_ operation: () throws -> T) throws(Stop) -> T {
        do {
            return try operation()
        } catch {
            throw .failed(.kernel(String(describing: error)))
        }
    }
}
```

`RebuildEngine.swift`:

```swift
public struct RebuildEngine<Kernel: GeometryKernel>: Sendable {
    public let kernel: Kernel

    public init(kernel: Kernel) {
        self.kernel = kernel
    }

    @concurrent
    public func rebuild(_ document: CADDocument) async throws -> RebuildResult {
        let parameters = ParameterTable(document.parameters)
        var parts: [PartResult] = []
        for part in document.parts {
            var builder = PartBuilder(kernel: kernel, parameters: parameters)
            var features: [FeatureResult] = []
            for feature in part.features {
                try Task.checkCancellation()
                features.append(builder.apply(feature))
            }
            parts.append(PartResult(id: part.id, name: part.name, features: features, bodies: try builder.bodyResults()))
        }
        return RebuildResult(parameters: parameters, parts: parts)
    }
}
```

`FeatureResult`, `BodyResult`, `PartResult`, `RebuildResult` need internal memberwise use only; that works inside the module.

- [ ] **Step 5: Run to verify pass** — `xcrun swift test --filter CADModelTests`.
- [ ] **Step 6: Commit** — `feat(model): rebuild feature trees through a geometry kernel`.

### Task 5: CADKernel adapter

**Files:**

- Modify: `Packages/CADModel/Sources/CADModelKernel/OCCTGeometryKernel.swift`
- Test: `Packages/CADModel/Tests/CADModelKernelTests/OCCTGeometryKernelTests.swift`

**Interfaces:**

- Consumes: `GeometryKernel`, `CADKernel.Kernel.*`, `CADKernel.Placement(translation:axis:angle:)` (radians), `SolidMetrics`, `KernelMesh`.
- Produces: `public struct OCCTGeometryKernel: GeometryKernel { typealias Body = Solid; init(tessellationTolerance: Double = 0.05) }`.

- [ ] **Step 1: Write the failing tests**

```swift
import CADModel
import CADModelKernel
import Foundation
import Testing

@Suite("OCCT geometry kernel")
struct OCCTGeometryKernelTests {
    let engine = RebuildEngine(kernel: OCCTGeometryKernel())

    private func approx(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-3) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= tolerance * max(1, abs(b))
    }

    @Test("A plate minus a hole, with a failing feature that does not stop the rest")
    func plateWithHole() async throws {
        let json = """
            {"format": 1, "units": "mm",
             "parameters": [{"name": "t", "expression": 10}],
             "parts": [{"name": "Plate", "features": [
               {"name": "Base", "kind": {"type": "box", "width": 60, "depth": 40, "height": "t"}},
               {"name": "Hole", "kind": {"type": "cylinder", "radius": 5, "height": "t",
                 "placement": {"translation": {"x": 30, "y": 20}}, "operation": {"mode": "cut", "body": "Body1"}}},
               {"name": "Bad", "kind": {"type": "cone", "bottomRadius": 3, "topRadius": 3, "height": 5}},
               {"name": "Knob", "kind": {"type": "sphere", "radius": 4,
                 "placement": {"translation": {"x": 30, "y": 20, "z": "t"}}, "operation": {"mode": "join", "body": "Body1"}}}
             ]}]}
            """
        let result = try await engine.rebuild(try CADDocument(json: Data(json.utf8)))
        let part = try #require(result.parts.first)
        #expect(part.features[0].status == .ok)
        #expect(part.features[1].status == .ok)
        guard case .failed(.kernel(let message)) = part.features[2].status else {
            Issue.record("expected a kernel failure, got \(part.features[2].status)")
            return
        }
        #expect(message.contains("cone radii must differ"))
        #expect(part.features[3].status == .ok)
        #expect(part.bodies.map(\.name) == ["Body1"])
        let body = try #require(part.bodies.first)
        let metrics = try #require(body.metrics)
        let expected = 60.0 * 40 * 10 - .pi * 25 * 10 + 2.0 / 3 * .pi * 64
        #expect(approx(metrics.volume, expected))
        #expect(metrics.isClosed)
        #expect(metrics.solidCount == 1)
        #expect((body.mesh?.triangleCount ?? 0) > 12)
        #expect(result.triangleCount == body.mesh?.triangleCount)
    }

    @Test("Rotations are given in degrees")
    func degrees() async throws {
        let box = Feature(name: "B", kind: .primitive(PrimitiveFeature(
            .box(width: 10, depth: 20, height: 5), placement: Placement(rotationDegrees: 90))))
        let result = try await engine.rebuild(CADDocument(parts: [Part(name: "P", features: [box])]))
        let metrics = try #require(result.bodies.first?.metrics)
        #expect(approx(metrics.boundsMin.x, -20))
        #expect(approx(metrics.boundsMax.x, 0))
        #expect(approx(metrics.boundsMax.y, 10))
        #expect(approx(metrics.boundsMax.z, 5))
    }

    @Test("Booleans, tori and transforms reach the kernel")
    func booleanAndTransform() async throws {
        let features = [
            Feature(name: "A", kind: .primitive(PrimitiveFeature(.box(width: 10, depth: 10, height: 10)))),
            Feature(name: "B", kind: .primitive(PrimitiveFeature(.box(width: 10, depth: 10, height: 10),
                placement: Placement(translation: Vector3(5, 0, 0))))),
            Feature(name: "U", kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: ["Body2"]))),
            Feature(name: "M", kind: .transform(TransformFeature(body: "Body1", placement: Placement(translation: Vector3(0, 0, 100))))),
            Feature(name: "T", kind: .primitive(PrimitiveFeature(.torus(majorRadius: 10, minorRadius: 2)))),
        ]
        let result = try await engine.rebuild(CADDocument(parts: [Part(name: "P", features: features)]))
        let part = try #require(result.parts.first)
        #expect(part.features.allSatisfy { $0.status == .ok })
        #expect(part.bodies.map(\.name) == ["Body1", "Body3"])
        let merged = try #require(part.bodies.first?.metrics)
        #expect(approx(merged.volume, 1500))
        #expect(approx(merged.boundsMin.z, 100))
        #expect(approx(part.bodies[1].metrics?.volume, 2 * .pi * .pi * 10 * 4))
    }
}
```

- [ ] **Step 2: Run to verify failure** — `xcrun swift test --filter CADModelKernelTests`: `OCCTGeometryKernel` not found.

- [ ] **Step 3: Implement**

```swift
import CADKernel
import CADModel

public struct OCCTGeometryKernel: GeometryKernel {
    public typealias Body = Solid

    public var tessellationTolerance: Double

    public init(tessellationTolerance: Double = 0.05) {
        self.tessellationTolerance = tessellationTolerance
    }

    public func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement) throws -> Solid {
        try Kernel.box(width: width, depth: depth, height: height, placement: CADKernel.Placement(placement))
    }

    public func cylinder(radius: Double, height: Double, placement: ResolvedPlacement) throws -> Solid {
        try Kernel.cylinder(radius: radius, height: height, placement: CADKernel.Placement(placement))
    }

    public func sphere(radius: Double, placement: ResolvedPlacement) throws -> Solid {
        try Kernel.sphere(radius: radius, placement: CADKernel.Placement(placement))
    }

    public func cone(bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement) throws -> Solid {
        try Kernel.cone(bottomRadius: bottomRadius, topRadius: topRadius, height: height, placement: CADKernel.Placement(placement))
    }

    public func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement) throws -> Solid {
        try Kernel.torus(majorRadius: majorRadius, minorRadius: minorRadius, placement: CADKernel.Placement(placement))
    }

    public func boolean(_ operation: CADModel.BooleanOperation, _ target: Solid, _ tool: Solid) throws -> Solid {
        let kernelOperation: CADKernel.BooleanOperation = switch operation {
        case .union: .union
        case .subtract: .subtract
        case .intersect: .intersect
        }
        return try Kernel.boolean(kernelOperation, target, tool)
    }

    public func transform(_ body: Solid, by placement: ResolvedPlacement) throws -> Solid {
        try Kernel.transform(body, by: CADKernel.Placement(placement))
    }

    public func metrics(of body: Solid) throws -> BodyMetrics {
        let metrics = try Kernel.metrics(of: body)
        return BodyMetrics(
            volume: metrics.volume, boundsMin: metrics.boundsMin, boundsMax: metrics.boundsMax,
            faceCount: metrics.faceCount, solidCount: metrics.solidCount,
            isValid: metrics.isValid, isClosed: metrics.isClosed)
    }

    public func mesh(of body: Solid) throws -> BodyMesh {
        let mesh = try Kernel.tessellate(body, tolerance: tessellationTolerance)
        return BodyMesh(positions: mesh.positions, normals: mesh.normals, indices: mesh.indices)
    }
}

extension CADKernel.Placement {
    init(_ placement: ResolvedPlacement) {
        self.init(
            translation: placement.translation,
            axis: placement.rotationAxis,
            angle: placement.rotationDegrees * .pi / 180
        )
    }
}
```

- [ ] **Step 4: Run to verify pass** — `cd Packages/CADModel && xcrun swift test` (both targets).
- [ ] **Step 5: Commit** — `feat(model): rebuild with the Open CASCADE kernel`.

### Task 6: Switch the app to `.cadmodel`

**Files:**

- Create: `3DModellerApp/Document/CADModelDocument.swift`, `3DModellerApp/Viewport/ViewportFrame.swift`, `3DModellerApp/Viewport/ViewportScene.swift`, `3DModellerApp/Views/FeatureOutlineView.swift`, `FeatureInspectorView.swift`, `FeatureDisplay.swift`, `ModelStatisticsView.swift`
- Modify: `ContentView.swift`, `Viewport3DView.swift`, `OrbitCamera.swift`, `ModellerApp.swift`, `project.yml`, `Package.swift`, `3DModellerApp/Info.plist` (regenerated), `3DModellerApp.xcodeproj` (regenerated)
- Delete: `3DModellerApp/Scene/`, `3DModellerApp/Tools/`, `3DModellerApp/Context/`, `Views/PropertiesInspectorView.swift`, `Views/SceneOutlineView.swift`; tests `AssistantIntegrationTests`, `CreateSolidToolTests`, `SceneDocumentTests`, `SceneManagerTests`, `SolidEntityTests`, `KernelMeshRealityKitTests`
- Test: `3DModellerAppTests/CADModelDocumentTests.swift`, `ViewportFrameTests.swift`, `FeatureDisplayTests.swift`, `OrbitCameraTests.swift`

**Interfaces:**

- Consumes: `CADDocument`, `RebuildEngine`, `RebuildResult`, `BodyMesh`, `FeatureStatus`, `OCCTGeometryKernel`.
- Produces (app-internal):
  - `final class CADModelDocument: ReferenceFileDocument { var model: CADDocument { get }; init(model: CADDocument = CADDocument()); @MainActor func edit(_ actionName: String, undoManager: UndoManager?, _ change: (inout CADDocument) -> Void) }`, `UTType.cadModel`.
  - `enum ViewportFrame { static func scenePosition(_: SIMD3<Float>) -> SIMD3<Float>; static func sceneDirection(_:) ; static func sceneBounds(of: RebuildResult?) -> SceneBounds? }`, `struct SceneBounds: Equatable { min, max: SIMD3<Float> }`, `extension BodyMesh { var meshDescriptor: MeshDescriptor }`.
  - `@MainActor final class ViewportScene { let root: Entity; func show(_ result: RebuildResult?) ; var bodyEntities: [ModelEntity] }`.
  - `OrbitCamera.target`, `OrbitCamera.framing(min:max:) -> OrbitCamera`.
  - `extension FeatureKind { var title: String; var symbolName: String; var properties: [FeatureProperty] }`, `struct FeatureProperty: Hashable { label: String; value: String }`, `extension FeatureStatus { var symbolName: String }`.

- [ ] **Step 1: Write the failing tests**

`CADModelDocumentTests.swift`:

```swift
import CADModel
import Foundation
import Testing
@testable import _D_Modeller

@Suite("CAD model document")
@MainActor
struct CADModelDocumentTests {
    private func undoManager() -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }

    private let sphere = Feature(name: "Ball", kind: .primitive(PrimitiveFeature(.sphere(radius: 5))))

    @Test("A new document is empty with one part and reads/writes the cadmodel type")
    func newDocument() {
        let document = CADModelDocument()
        #expect(document.model == CADDocument())
        #expect(CADModelDocument.readableContentTypes == [.cadModel])
        #expect(UTType.cadModel.identifier == "com.example.3dmodeller.cadmodel")
        #expect(UTType.cadModel.preferredFilenameExtension == "cadmodel")
    }

    @Test("Edits register a named undo step that restores the previous value, and redo reapplies it")
    func undoRedo() {
        let undoManager = undoManager()
        let document = CADModelDocument()
        let sphere = sphere
        document.edit("Add Ball", undoManager: undoManager) { $0.parts[0].features.append(sphere) }
        #expect(document.model.parts[0].features == [sphere])
        #expect(undoManager.undoActionName == "Add Ball")

        undoManager.undo()
        #expect(document.model.parts[0].features.isEmpty)
        #expect(undoManager.redoActionName == "Add Ball")

        undoManager.redo()
        #expect(document.model.parts[0].features == [sphere])
        #expect(undoManager.canUndo)
    }

    @Test("An edit that changes nothing registers nothing")
    func noOpEdit() {
        let undoManager = undoManager()
        let document = CADModelDocument()
        document.edit("Nothing", undoManager: undoManager) { _ in }
        #expect(!undoManager.canUndo)
    }

    @Test("Edits notify observers")
    func publishes() {
        let document = CADModelDocument()
        var notified = 0
        let subscription = document.objectWillChange.sink { notified += 1 }
        let sphere = sphere
        document.edit("Add Ball", undoManager: nil) { $0.parts[0].features.append(sphere) }
        #expect(notified == 1)
        subscription.cancel()
    }
}
```

(`import Combine` and `import UniformTypeIdentifiers` at the top as needed.)

`ViewportFrameTests.swift`:

```swift
import CADModel
import RealityKit
import Testing
@testable import _D_Modeller

@Suite("Viewport frame")
@MainActor
struct ViewportFrameTests {
    @Test("Model millimetres, Z-up, become scene metres, Y-up")
    func positions() {
        #expect(ViewportFrame.scenePosition(SIMD3(1000, 2000, 3000)) == SIMD3(1, 3, -2))
        #expect(ViewportFrame.sceneDirection(SIMD3(0, 0, 1)) == SIMD3(0, 1, 0))
    }

    @Test("A body mesh becomes a Y-up MeshResource with normals rotated alongside")
    func meshDescriptor() throws {
        let mesh = BodyMesh(
            positions: [SIMD3(0, 0, 100), SIMD3(100, 0, 100), SIMD3(0, 50, 100)],
            normals: Array(repeating: SIMD3(0, 0, 1), count: 3),
            indices: [0, 1, 2])
        let descriptor = mesh.meshDescriptor
        let normals = Array(try #require(descriptor.normals?.elements))
        #expect(normals.allSatisfy { $0 == SIMD3(0, 1, 0) })
        let bounds = try MeshResource.generate(from: [descriptor]).bounds
        #expect(abs(bounds.min.y - 0.1) < 1e-6)
        #expect(abs(bounds.extents.x - 0.1) < 1e-6)
        #expect(abs(bounds.extents.z - 0.05) < 1e-6)
    }

    private func rebuild(_ document: CADDocument) async throws -> RebuildResult {
        try await RebuildEngine(kernel: OCCTGeometryKernel()).rebuild(document)
    }

    @Test("An empty result has no bounds")
    func emptyResultHasNoBounds() async throws {
        #expect(ViewportFrame.sceneBounds(of: nil) == nil)
        #expect(ViewportFrame.sceneBounds(of: try await rebuild(CADDocument())) == nil)
    }

    @Test("Scene bounds and entities come from real bodies")
    func sceneShowsBodies() async throws {
        let box = Feature(name: "B", kind: .primitive(PrimitiveFeature(.box(width: 100, depth: 50, height: 20))))
        let result = try await rebuild(CADDocument(parts: [Part(name: "P", features: [box])]))
        let bounds = try #require(ViewportFrame.sceneBounds(of: result))
        #expect(abs(bounds.min.z - -0.05) < 1e-4)
        #expect(abs(bounds.max.y - 0.02) < 1e-4)
        let scene = ViewportScene()
        scene.show(result)
        #expect(scene.bodyEntities.map(\.name) == ["Body1"])
        scene.show(nil)
        #expect(scene.bodyEntities.isEmpty)
    }
}
```

Imports: `CADModel`, `CADModelKernel`, `RealityKit`, `Testing`, `@testable import _D_Modeller`.


`FeatureDisplayTests.swift`:

```swift
import CADModel
import Testing
@testable import _D_Modeller

@Suite("Feature display")
struct FeatureDisplayTests {
    @Test("A box lists its dimensions by axis, its placement and its operation")
    func boxProperties() {
        let kind = FeatureKind.primitive(PrimitiveFeature(
            .box(width: "w", depth: 40, height: 10),
            placement: Placement(translation: Vector3(1, 2, 3), rotationAxis: Vector3(0, 0, 1), rotationDegrees: 45),
            operation: .cut("Body1")))
        #expect(kind.title == "Box")
        #expect(kind.properties == [
            FeatureProperty(label: "Width (X)", value: "w"),
            FeatureProperty(label: "Depth (Y)", value: "40"),
            FeatureProperty(label: "Height (Z)", value: "10"),
            FeatureProperty(label: "Position", value: "1, 2, 3"),
            FeatureProperty(label: "Rotation", value: "45° about 0, 0, 1"),
            FeatureProperty(label: "Operation", value: "Cut Body1"),
        ])
    }

    @Test("Booleans and transforms list their bodies")
    func booleanAndTransform() {
        #expect(FeatureKind.boolean(BooleanFeature(operation: .subtract, target: "Body1", tools: ["Body2", "Body3"])).properties == [
            FeatureProperty(label: "Operation", value: "Subtract"),
            FeatureProperty(label: "Target", value: "Body1"),
            FeatureProperty(label: "Tools", value: "Body2, Body3"),
        ])
        #expect(FeatureKind.transform(TransformFeature(body: "Body2", placement: .identity)).properties == [
            FeatureProperty(label: "Body", value: "Body2"),
            FeatureProperty(label: "Position", value: "0, 0, 0"),
            FeatureProperty(label: "Rotation", value: "0° about 0, 0, 1"),
        ])
    }

    @Test("Every kind has a title and a symbol", arguments: [
        FeatureKind.primitive(PrimitiveFeature(.sphere(radius: 1))),
        .primitive(PrimitiveFeature(.cylinder(radius: 1, height: 1))),
        .primitive(PrimitiveFeature(.cone(bottomRadius: 1, topRadius: 0, height: 1))),
        .primitive(PrimitiveFeature(.torus(majorRadius: 2, minorRadius: 1))),
    ])
    func titles(kind: FeatureKind) {
        #expect(!kind.title.isEmpty)
        #expect(!kind.symbolName.isEmpty)
    }

    @Test("Statuses map to distinct symbols")
    func statusSymbols() {
        let symbols: Set = [
            FeatureStatus.ok.symbolName, FeatureStatus.failed(.kernel("x")).symbolName,
            FeatureStatus.skipped(dependsOn: "A").symbolName, FeatureStatus.suppressed.symbolName,
        ]
        #expect(symbols.count == 4)
    }
}
```

`OrbitCameraTests.swift` — add:

```swift
    @Test
    func testFramingCentresOnTheBoundsAndBacksOffWithTheirSize() {
        let small = OrbitCamera.framing(min: SIMD3(-0.05, 0, -0.05), max: SIMD3(0.05, 0.02, 0.05))
        let large = OrbitCamera.framing(min: SIMD3(-1, 0, -1), max: SIMD3(1, 1, 1))
        #expect(simd_distance(small.target, SIMD3(0, 0.01, 0)) < 1e-6)
        #expect(small.distance < large.distance)
        #expect(OrbitCamera.distanceRange.contains(small.distance))
        #expect(simd_distance(small.position, small.target) - small.distance < 1e-4)
    }

    @Test
    func testFramingIgnoresMissingBounds() {
        #expect(OrbitCamera.framing(nil) == OrbitCamera())
    }
```

`testDefaultCameraLooksDownOnTheGround` keeps holding because the default target is the origin.

- [ ] **Step 2: Run to verify failure** — `xcodegen generate && xcodebuild … test`: compile errors.

- [ ] **Step 3: Implement**

`CADModelDocument.swift`:

```swift
import CADModel
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

extension UTType {
    static var cadModel: UTType { UTType(exportedAs: "com.example.3dmodeller.cadmodel") }
}

/// A reference document so SwiftUI tracks unsaved changes through the window's undo manager, where `edit` records
/// each change; a `FileDocument` binding would add an unnamed undo step of its own on every write.
final class CADModelDocument: ReferenceFileDocument {
    private let storage: Mutex<CADDocument>

    var model: CADDocument { storage.withLock { $0 } }

    static var readableContentTypes: [UTType] { [.cadModel] }

    init(model: CADDocument = CADDocument()) {
        storage = Mutex(model)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        storage = Mutex(try CADDocument(json: data))
    }

    func snapshot(contentType: UTType) throws -> CADDocument { model }

    func fileWrapper(snapshot: CADDocument, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.jsonData())
    }

    @MainActor
    func edit(_ actionName: String, undoManager: UndoManager?, _ change: (inout CADDocument) -> Void) {
        var updated = model
        change(&updated)
        replace(with: updated, actionName: actionName, undoManager: undoManager)
    }

    @MainActor
    private func replace(with new: CADDocument, actionName: String, undoManager: UndoManager?) {
        let old = model
        guard new != old else { return }
        objectWillChange.send()
        storage.withLock { $0 = new }
        guard let undoManager else { return }
        let opensGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if opensGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { document in
            document.replace(with: old, actionName: actionName, undoManager: undoManager)
        }
        undoManager.setActionName(actionName)
        if opensGroup { undoManager.endUndoGrouping() }
    }
}
```

`ViewportFrame.swift`:

```swift
import CADModel
import RealityKit

/// The model is millimetres with Z up; RealityKit is metres with Y up.
enum ViewportFrame {
    static let metresPerMillimetre: Float = 0.001

    static func sceneDirection(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(v.x, v.z, -v.y) }

    static func scenePosition(_ p: SIMD3<Float>) -> SIMD3<Float> { sceneDirection(p) * metresPerMillimetre }

    static func sceneBounds(of result: RebuildResult?) -> SceneBounds? {
        let corners = (result?.bodies ?? []).compactMap(\.metrics).flatMap { metrics in
            [metrics.boundsMin, metrics.boundsMax].map { scenePosition(SIMD3<Float>($0)) }
        }
        guard let first = corners.first else { return nil }
        return corners.dropFirst().reduce(SceneBounds(min: first, max: first)) {
            SceneBounds(min: simd_min($0.min, $1), max: simd_max($0.max, $1))
        }
    }
}

struct SceneBounds: Equatable {
    var min: SIMD3<Float>
    var max: SIMD3<Float>
}

extension BodyMesh {
    var meshDescriptor: MeshDescriptor {
        var descriptor = MeshDescriptor(name: "body")
        descriptor.positions = MeshBuffer(positions.map(ViewportFrame.scenePosition))
        descriptor.normals = MeshBuffer(normals.map(ViewportFrame.sceneDirection))
        descriptor.primitives = .triangles(indices)
        return descriptor
    }
}
```



`ViewportScene.swift`:

```swift
import CADModel
import RealityKit
import SwiftUI

@MainActor
final class ViewportScene {
    let root = Entity()
    private let bodies = Entity()

    private static let palette: [NSColor] = [
        NSColor(red: 0.62, green: 0.70, blue: 0.80, alpha: 1),
        NSColor(red: 0.80, green: 0.66, blue: 0.52, alpha: 1),
        NSColor(red: 0.60, green: 0.78, blue: 0.62, alpha: 1),
        NSColor(red: 0.78, green: 0.62, blue: 0.76, alpha: 1),
    ]

    init() {
        root.addChild(Self.makeGrid())
        root.addChild(Self.makeLight())
        root.addChild(bodies)
    }

    var bodyEntities: [ModelEntity] { bodies.children.compactMap { $0 as? ModelEntity } }

    func show(_ result: RebuildResult?) {
        bodies.children.removeAll()
        for (index, body) in (result?.bodies ?? []).enumerated() {
            guard let mesh = body.mesh, mesh.triangleCount > 0,
                let resource = try? MeshResource.generate(from: [mesh.meshDescriptor])
            else { continue }
            let material = SimpleMaterial(color: Self.palette[index % Self.palette.count], roughness: 0.6, isMetallic: false)
            let entity = ModelEntity(mesh: resource, materials: [material])
            entity.name = body.name
            bodies.addChild(entity)
        }
    }

    private static func makeGrid() -> Entity {
        let grid = Entity()
        let halfExtent: Float = 0.25
        let spacing: Float = 0.01
        let material = SimpleMaterial(color: .gray.withAlphaComponent(0.3), isMetallic: false)
        for offset in stride(from: -halfExtent, through: halfExtent, by: spacing) {
            let alongX = ModelEntity(mesh: .generateBox(width: halfExtent * 2, height: 0.0002, depth: 0.0002), materials: [material])
            alongX.position = [0, 0, offset]
            let alongZ = ModelEntity(mesh: .generateBox(width: 0.0002, height: 0.0002, depth: halfExtent * 2), materials: [material])
            alongZ.position = [offset, 0, 0]
            grid.addChild(alongX)
            grid.addChild(alongZ)
        }
        return grid
    }

    private static func makeLight() -> Entity {
        let light = DirectionalLight()
        light.light.intensity = 3000
        light.look(at: .zero, from: [0.4, 1, 0.7], relativeTo: nil)
        return light
    }
}
```

`OrbitCamera.swift`: add `var target: SIMD3<Float> = .zero`; `distanceRange = 0.05...50`; default `distance = 0.4`; `position` returns `target + offset`; add

```swift
    static func framing(_ bounds: SceneBounds?) -> OrbitCamera {
        guard let bounds else { return OrbitCamera() }
        var camera = OrbitCamera()
        camera.target = (bounds.min + bounds.max) / 2
        let size = simd_length(bounds.max - bounds.min)
        camera.distance = min(max(size * 1.8, distanceRange.lowerBound), distanceRange.upperBound)
        return camera
    }

    static func framing(min: SIMD3<Float>, max: SIMD3<Float>) -> OrbitCamera {
        framing(SceneBounds(min: min, max: max))
    }
```

`Viewport3DView.swift`: takes `let result: RebuildResult?`; `@State private var scene = ViewportScene()`; `@State private var hasFramed = false`; RealityView `make` adds `scene.root` and camera; `update` aims camera at `camera.target`; `.onChange(of: result, initial: true) { scene.show(result); if !hasFramed, let bounds = ViewportFrame.sceneBounds(of: result) { camera = .framing(bounds); hasFramed = true } }`. Remove the tap-to-deselect gesture and the dead highlight extension.

`FeatureDisplay.swift`:

```swift
import CADModel
import SwiftUI

struct FeatureProperty: Hashable {
    let label: String
    let value: String
}

extension FeatureKind {
    var title: String {
        switch self {
        case .primitive(let primitive):
            switch primitive.shape {
            case .box: "Box"
            case .cylinder: "Cylinder"
            case .sphere: "Sphere"
            case .cone: "Cone"
            case .torus: "Torus"
            }
        case .boolean: "Boolean"
        case .transform: "Transform"
        }
    }

    var symbolName: String {
        switch self {
        case .primitive(let primitive):
            switch primitive.shape {
            case .box: "cube"
            case .cylinder: "cylinder"
            case .sphere: "circle"
            case .cone: "cone"
            case .torus: "circle.circle"
            }
        case .boolean: "square.on.square.intersection.dashed"
        case .transform: "move.3d"
        }
    }

    var properties: [FeatureProperty] {
        switch self {
        case .primitive(let primitive):
            return primitive.shape.properties + primitive.placement.properties
                + [FeatureProperty(label: "Operation", value: primitive.operation.label)]
        case .boolean(let boolean):
            return [
                FeatureProperty(label: "Operation", value: boolean.operation.rawValue.capitalized),
                FeatureProperty(label: "Target", value: boolean.target),
                FeatureProperty(label: "Tools", value: boolean.tools.joined(separator: ", ")),
            ]
        case .transform(let transform):
            return [FeatureProperty(label: "Body", value: transform.body)] + transform.placement.properties
        }
    }
}

extension PrimitiveShape {
    var properties: [FeatureProperty] {
        switch self {
        case .box(let width, let depth, let height):
            [.init(label: "Width (X)", value: width.description), .init(label: "Depth (Y)", value: depth.description),
             .init(label: "Height (Z)", value: height.description)]
        case .cylinder(let radius, let height):
            [.init(label: "Radius", value: radius.description), .init(label: "Height (Z)", value: height.description)]
        case .sphere(let radius):
            [.init(label: "Radius", value: radius.description)]
        case .cone(let bottomRadius, let topRadius, let height):
            [.init(label: "Bottom radius", value: bottomRadius.description), .init(label: "Top radius", value: topRadius.description),
             .init(label: "Height (Z)", value: height.description)]
        case .torus(let majorRadius, let minorRadius):
            [.init(label: "Major radius", value: majorRadius.description), .init(label: "Minor radius", value: minorRadius.description)]
        }
    }
}

extension Placement {
    var properties: [FeatureProperty] {
        [
            FeatureProperty(label: "Position", value: translation.label),
            FeatureProperty(label: "Rotation", value: "\(rotationDegrees)° about \(rotationAxis.label)"),
        ]
    }
}

extension Vector3 {
    var label: String { "\(x), \(y), \(z)" }
}

extension SolidOperation {
    var label: String {
        switch self {
        case .newBody: "New body"
        case .join(let body): "Join \(body)"
        case .cut(let body): "Cut \(body)"
        case .intersect(let body): "Intersect \(body)"
        }
    }
}

extension FeatureStatus {
    var symbolName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .skipped: "arrow.uturn.down.circle"
        case .suppressed: "pause.circle"
        }
    }

    var tint: Color {
        switch self {
        case .ok: .green
        case .failed: .red
        case .skipped: .orange
        case .suppressed: .secondary
        }
    }
}
```

`FeatureOutlineView.swift`:

```swift
import CADModel
import SwiftUI

struct FeatureOutlineView: View {
    let model: CADDocument
    let result: RebuildResult?
    @Binding var selection: UUID?
    let setSuppressed: (Feature, Bool) -> Void
    let delete: (Feature) -> Void

    var body: some View {
        List(selection: $selection) {
            if !model.parameters.isEmpty {
                Section("Parameters") {
                    ForEach(model.parameters, id: \.name) { parameter in
                        ParameterRow(parameter: parameter, value: result?.parameters.value(of: parameter.name))
                    }
                }
            }
            ForEach(model.parts) { part in
                Section(part.name) {
                    if part.features.isEmpty {
                        Text("No features").foregroundStyle(.secondary).italic()
                    }
                    ForEach(part.features) { feature in
                        FeatureRow(feature: feature, result: result?.feature(id: feature.id))
                            .tag(feature.id)
                            .contextMenu {
                                Button(feature.suppressed ? "Unsuppress" : "Suppress") {
                                    setSuppressed(feature, !feature.suppressed)
                                }
                                Divider()
                                Button("Delete", role: .destructive) { delete(feature) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct ParameterRow: View {
    let parameter: Parameter
    let value: Result<Double, ExpressionError>?

    var body: some View {
        HStack {
            Text(parameter.name)
            Spacer()
            switch value {
            case .success(let number)?:
                Text(Scalar.number(number).description).foregroundStyle(.secondary).monospacedDigit()
            case .failure(let error)?:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).help(error.description)
            case nil:
                EmptyView()
            }
        }
        .help("\(parameter.name) = \(parameter.expression)")
    }
}

private struct FeatureRow: View {
    let feature: Feature
    let result: FeatureResult?

    var body: some View {
        HStack {
            Image(systemName: feature.kind.symbolName).frame(width: 20).foregroundStyle(.secondary)
            Text(feature.name).lineLimit(1).strikethrough(feature.suppressed)
            Spacer()
            if let status = result?.status {
                Image(systemName: status.symbolName).foregroundStyle(status.tint).help(status.description)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}
```

`FeatureInspectorView.swift`:

```swift
import CADModel
import SwiftUI

struct FeatureInspectorView: View {
    let feature: Feature?
    let result: FeatureResult?

    var body: some View {
        if let feature {
            Form {
                Section {
                    LabeledContent("Name", value: feature.name)
                    LabeledContent("Type", value: feature.kind.title)
                    if let body = result?.body { LabeledContent("Body", value: body) }
                    if let status = result?.status {
                        LabeledContent("Status") {
                            Label(status.description, systemImage: status.symbolName)
                                .foregroundStyle(status.tint)
                                .textSelection(.enabled)
                        }
                    }
                }
                Section("Parameters") {
                    ForEach(feature.kind.properties, id: \.self) { property in
                        LabeledContent(property.label, value: property.value)
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "No Selection", systemImage: "cube.transparent",
                description: Text("Select a feature in the outline to see its parameters"))
        }
    }
}
```

`ModelStatisticsView.swift`:

```swift
import CADModel
import SwiftUI

struct ModelStatisticsView: View {
    let result: RebuildResult?

    var body: some View {
        HStack(spacing: 16) {
            if let result {
                Label("\(result.bodies.count) bodies", systemImage: "cube")
                Label("\(result.triangleCount) triangles", systemImage: "triangle")
                if result.failedFeatureCount > 0 {
                    Label("\(result.failedFeatureCount) failed", systemImage: "xmark.octagon").foregroundStyle(.red)
                }
            } else {
                Label("Rebuilding…", systemImage: "hourglass")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}
```

`ContentView.swift`: replace `SceneManager` with:

```swift
    @ObservedObject var document: CADModelDocument
    @Environment(\.undoManager) private var undoManager
    @State private var result: RebuildResult?
    @State private var selection: UUID?

    private static let engine = RebuildEngine(kernel: OCCTGeometryKernel())
```

- sidebar: `FeatureOutlineView(model: document.model, result: result, selection: $selection, setSuppressed: { feature, suppressed in document.edit(suppressed ? "Suppress \(feature.name)" : "Unsuppress \(feature.name)", undoManager: undoManager) { _ = $0.updateFeature(id: feature.id) { $0.suppressed = suppressed } } }, delete: { feature in document.edit("Delete \(feature.name)", undoManager: undoManager) { _ = $0.removeFeature(id: feature.id) } })`
- detail: `Viewport3DView(result: result).overlay(alignment: .bottom) { ModelStatisticsView(result: result).padding() }`
- `.task(id: document.model) { if let rebuilt = try? await Self.engine.rebuild(document.model) { result = rebuilt } }` — cancellation of the previous task makes `rebuild` throw, so a stale result never lands.
- `.navigationTitle` removed (DocumentGroup shows the file name).
- Inspector `.properties` tab: `FeatureInspectorView(feature: selection.flatMap(document.model.feature(id:)), result: selection.flatMap { result?.feature(id: $0) })`.
- Assistant: tools `[FetchTool(), CalculatorTool(), TimeTool()]`, `contextProvider: { EmptyContext() }`, system prompt stating it cannot edit the model yet (modelling tools arrive with the next release) and that the model uses millimetres.
- Preview: `ContentView(document: CADModelDocument())`.

`ModellerApp.swift`: `DocumentGroup(newDocument: { CADModelDocument() })`.

`project.yml`: package `CADModel: path: Packages/CADModel` replaces `CADKernel`; dependencies `CADModel/CADModel` and `CADModel/CADModelKernel`; document type:

```yaml
CFBundleDocumentTypes:
  - CFBundleTypeName: CAD Model
    CFBundleTypeRole: Editor
    LSHandlerRank: Owner
    LSItemContentTypes:
      - com.example.3dmodeller.cadmodel
UTExportedTypeDeclarations:
  - UTTypeIdentifier: com.example.3dmodeller.cadmodel
    UTTypeDescription: 3D Modeller CAD Model
    UTTypeConformsTo:
      - public.json
      - public.content
    UTTypeTagSpecification:
      public.filename-extension:
        - cadmodel
```

`Package.swift` (root): replace `.package(path: "Packages/CADKernel")` with `.package(path: "Packages/CADModel")`; target dependencies `.product(name: "CADModel", package: "CADModel")`, `.product(name: "CADModelKernel", package: "CADModel")`.

- [ ] **Step 4: Delete the old model** (files listed above) and run `xcodegen generate`.

- [ ] **Step 5: Run to verify pass**

Run: `xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp -destination 'platform=macOS' test > <scratch>/app-test.log 2>&1; tail -30 <scratch>/app-test.log`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commits** (each builds and tests green):
  1. `feat(app): open and save cadmodel documents` — `CADModelDocument`, UTType, project.yml document type, ModellerApp, ContentView switch, outline/inspector/statistics, viewport rendering, deletions of the old model and its tests, new tests. (This is one concern — replacing the document model — and cannot be split without an intermediate commit that fails to build.)
  2. `feat(viewport): frame the camera on the model` — `OrbitCamera.target`/`framing`, framing on first result, tests.

### Task 7: Documentation and the verify skill

**Files:** `CLAUDE.md`, `README.md`, `.claude/skills/verify/SKILL.md`

- [ ] **Step 1: CLAUDE.md** — architecture lists the packages (`SwiftUIAssistant`, `SwiftUIAssistantTools`, `CADKernel`, `CADModel` with `CADModelKernel`) and the app (`CADModelDocument`, rebuild via `.task(id:)`, viewport); build commands include `cd Packages/CADModel && xcrun swift test`; replace `swift build/test` with `xcrun swift …`; key data flow for rebuild; remove `SceneManager` and old tools; project configuration mentions `com.example.3dmodeller.cadmodel` (`.cadmodel`).
- [ ] **Step 2: README.md** — features: parametric documents, parameters with expressions, primitives/booleans/transforms, rebuild status, `.cadmodel`; usage section says modelling tools arrive with the assistant tools; test commands include CADKernel and CADModel; architecture tree updated.
- [ ] **Step 3: verify SKILL.md** — open a hand-written `.cadmodel` (include a sample: box minus cylinder plus a failing cone), surfaces (outline statuses with tooltips, inspector read-only, status bar, context-menu suppress/delete, Edit ▸ Undo), save/diff via `python3 -m json.tool`; keep "When you're done" unchanged.
- [ ] **Step 4: Commit** — `docs: describe the cadmodel document model`.

### Task 8: Runtime verification (no commit)

- [ ] Build to a scratch derived-data path, open a hand-written `.cadmodel` (box 60×40×10 minus a centred cylinder r=5, plus a cone with equal radii), and confirm: viewport shows the plate with a hole, outline shows ✓ ✓ ✗ with the failure tooltip, status bar shows `1 bodies`, `N triangles`, `1 failed`; Suppress the cone via context menu → failure count drops; ⌘Z restores it; ⌘S writes sorted, pretty JSON. Then follow "When you're done".
