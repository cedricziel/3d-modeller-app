# CAD 01: Kernel operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `CADKernel` the operations PR 2's document model replays: placed primitive solids, booleans, transforms, and per-body validity and metrics, all safe to call from background tasks.

**Architecture:** Everything stays in `Packages/CADKernel` as static functions on `Kernel` that take and return the opaque `Solid`. A new pure value type `Placement` (translation plus axis-angle rotation) positions primitives and drives transforms. Every OCCT call runs inside `OCCTSerial.withLock {}`; every OCCT failure becomes a `KernelError`.

**Tech Stack:** Swift 6.1 tools, Swift Testing, OCCTSwift 3.0.0, simd.

**Spec:** `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md` (PR 1 row), with `docs/superpowers/specs/2026-09-26-geometry-kernel.md` and `docs/spikes/2026-09-26-occt-kernel.md` as background.

## Global Constraints

- macOS 26, Apple Silicon only, Swift 6 strict concurrency. Use `xcrun swift`, never bare `swift`.
- Only `CADKernel` imports OCCTSwift.
- No C++ exception may cross into Swift. Every kernel call returns a typed error.
- Every PR in the stack builds, passes its tests and leaves `main` shippable on its own.
- The existing `extrudeRectangle`, `fillet`, `tessellate` and `metrics` keep their behaviour: the app calls them until PR 2.
- Tests use Swift Testing (`@Suite`, `@Test`, `#expect`).

## Conventions fixed by this plan

- Units are plain `Double` lengths (the model uses millimetres; the kernel doesn't care). Angles are radians.
- Primitive local frames, before placement:
  - `box(width:depth:height:)`: corner at the origin, occupies `[0,width]×[0,depth]×[0,height]` (X, Y, Z).
  - `cylinder` and `cone`: base circle centred on the origin in XY, axis +Z, occupies `z ∈ [0,height]`.
  - `sphere` and `torus`: centred on the origin; the torus axis is +Z.
- A placement maps a local point `p` to `R·p + t`: rotate about the local origin, then translate.
- A boolean result can hold several disjoint solids. It stays one `Solid`; `SolidMetrics.solidCount` reports how many, and `Kernel.solids(of:)` splits them.
- A boolean that leaves no solid at all throws `KernelError.emptyResult`.

## File Structure

- Create `Sources/CADKernel/Placement.swift`: the `Placement` value type (pure Swift + simd).
- Create `Sources/CADKernel/Kernel+Primitives.swift`: `box`, `cylinder`, `sphere`, `cone`, `torus`.
- Create `Sources/CADKernel/Kernel+Booleans.swift`: `BooleanOperation`, `boolean`, `solids(of:)`.
- Create `Sources/CADKernel/Kernel+Transform.swift`: `transform(_:by:)` and the `Placement` to OCCT matrix conversion.
- Modify `Sources/CADKernel/Solid.swift`: extend `SolidMetrics`, add `KernelError.emptyResult`.
- Modify `Sources/CADKernel/Kernel.swift`: `metrics(of:)` fills the new fields.
- Tests: `MetricsTests.swift`, `PlacementTests.swift`, `PrimitiveTests.swift`, `BooleanTests.swift`, `ConcurrencyTests.swift`, plus a shared `Approx.swift` helper.

## Review Focus

1. NaN or infinite dimensions (an agent computes `0/0`): expect `invalidDimensions`, never a crash or a NaN-volume solid. Pinned in Task 3 (`rejectsNonFinite`).
2. A zero rotation axis in a placement: expect `invalidDimensions`, not a silently unrotated or NaN-filled solid. Pinned in Task 2 (`zeroAxis`).
3. Degenerate primitives (cone with equal radii or both radii zero, torus with minor ≥ major radius): expect `invalidDimensions` before OCCT sees them. Pinned in Task 3 (`rejectsDegenerateCone`, `rejectsSelfIntersectingTorus`).
4. Booleans with no overlap or total removal: intersecting disjoint solids or subtracting a larger tool must throw `emptyResult`, and a union of disjoint solids must report `solidCount == 2`. Pinned in Task 4.
5. Concurrent calls from many tasks: results must match the serial answer exactly. Pinned in Task 5.

---

### Task 1: Richer solid metrics

**Files:**

- Modify: `Packages/CADKernel/Sources/CADKernel/Solid.swift`
- Modify: `Packages/CADKernel/Sources/CADKernel/Kernel.swift`
- Create: `Packages/CADKernel/Tests/CADKernelTests/Approx.swift`
- Create: `Packages/CADKernel/Tests/CADKernelTests/MetricsTests.swift`

**Interfaces:**

- Produces: `SolidMetrics.faceCount: Int`, `.solidCount: Int`, `.isClosed: Bool`; `KernelError.emptyResult`; test helpers `approx(_:_:tolerance:)` for `Double` and `SIMD3<Double>`.

- [ ] **Step 1: Write the failing test**

`Approx.swift`:

```swift
func approx(_ a: Double, _ b: Double, tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance * max(1, abs(b))
}

func approx(_ a: SIMD3<Double>, _ b: SIMD3<Double>, tolerance: Double = 1e-6) -> Bool {
    approx(a.x, b.x, tolerance: tolerance) && approx(a.y, b.y, tolerance: tolerance)
        && approx(a.z, b.z, tolerance: tolerance)
}
```

`MetricsTests.swift`:

```swift
import OCCTSwift
import Testing
@testable import CADKernel

@Suite("Solid metrics")
struct MetricsTests {
    @Test("An extruded block is one closed solid with six faces")
    func closedBlock() throws {
        let metrics = try Kernel.metrics(of: Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5))

        #expect(metrics.solidCount == 1)
        #expect(metrics.faceCount == 6)
        #expect(metrics.isClosed)
    }

    @Test("A block missing one face is reported as not closed")
    func openShell() throws {
        let open = try OCCTSerial.withLock {
            let block = try #require(Shape.box(width: 1, height: 1, depth: 1))
            let faces = block.subShapes(ofType: .face)
            return Solid(shape: try #require(Shape.compound(Array(faces.dropFirst()))))
        }
        let metrics = try Kernel.metrics(of: open)

        #expect(metrics.solidCount == 0)
        #expect(!metrics.isClosed)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/CADKernel && xcrun swift test --filter MetricsTests`
Expected: compile error, `faceCount` etc. not members of `SolidMetrics`.

- [ ] **Step 3: Implement**

`Solid.swift`, `SolidMetrics` becomes:

```swift
public struct SolidMetrics: Sendable, Equatable {
    public let volume: Double
    public let boundsMin: SIMD3<Double>
    public let boundsMax: SIMD3<Double>
    public let faceCount: Int
    public let edgeCount: Int
    public let solidCount: Int
    public let isValid: Bool
    public let isClosed: Bool
}
```

and `KernelError` gains `case emptyResult` with description `"The operation left no solid"`.

`Kernel.metrics(of:)`:

```swift
public static func metrics(of solid: Solid) throws -> SolidMetrics {
    try OCCTSerial.withLock {
        let shape = solid.shape
        guard let volume = shape.volume, let bounds = shape.boundingBox else {
            throw KernelError.operationFailed("measure the solid")
        }
        let solids = shape.solids
        return SolidMetrics(
            volume: volume,
            boundsMin: bounds.min,
            boundsMax: bounds.max,
            faceCount: shape.faceCount,
            edgeCount: shape.edgeCount,
            solidCount: solids.count,
            isValid: shape.isValid,
            isClosed: !solids.isEmpty && solids.allSatisfy(\.isValidSolid)
                && shape.freeBounds(sewingTolerance: 0) == nil
        )
    }
}
```

- [ ] **Step 4: Run all package tests** — `xcrun swift test`; expected all pass.
- [ ] **Step 5: Commit** — `feat(kernel): report face count, solid count and closure`

### Task 2: Placement and transform

**Files:**

- Create: `Sources/CADKernel/Placement.swift`, `Sources/CADKernel/Kernel+Transform.swift`
- Test: `Tests/CADKernelTests/PlacementTests.swift`

**Interfaces:**

- Consumes: `Kernel.extrudeRectangle`, `Kernel.metrics`, `approx`.
- Produces:
  - `public struct Placement: Sendable, Hashable, Codable { var translation: SIMD3<Double>; var axis: SIMD3<Double>; var angle: Double; init(translation: SIMD3<Double> = .zero, axis: SIMD3<Double> = SIMD3(0, 0, 1), angle: Double = 0); static let identity }`
  - `public static func transform(_ solid: Solid, by placement: Placement) throws -> Solid`
  - internal `static func placed(_ shape: Shape, _ placement: Placement) throws -> Shape` (call under the lock) and `static func validate(_ placement: Placement) throws`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import CADKernel

@Suite("Placement and transform")
struct PlacementTests {
    private func block() throws -> Solid {
        try Kernel.extrudeRectangle(width: 2, height: 4, depth: 1)  // x ∈ [-1,1], y ∈ [-2,2], z ∈ [0,1]
    }

    @Test("Translating moves the bounds and keeps the volume")
    func translate() throws {
        let moved = try Kernel.transform(block(), by: Placement(translation: SIMD3(10, 0, -1)))
        let metrics = try Kernel.metrics(of: moved)

        #expect(approx(metrics.boundsMin, SIMD3(9, -2, -1)))
        #expect(approx(metrics.boundsMax, SIMD3(11, 2, 0)))
        #expect(approx(metrics.volume, 8))
    }

    @Test("A quarter turn about Z swaps the X and Y extents")
    func rotate() throws {
        let turned = try Kernel.transform(block(), by: Placement(angle: .pi / 2))
        let metrics = try Kernel.metrics(of: turned)

        #expect(approx(metrics.boundsMin, SIMD3(-2, -1, 0)))
        #expect(approx(metrics.boundsMax, SIMD3(2, 1, 1)))
    }

    @Test("Rotation applies about the origin before the translation")
    func rotateThenTranslate() throws {
        let placement = Placement(translation: SIMD3(0, 0, 5), axis: SIMD3(1, 0, 0), angle: .pi / 2)
        let metrics = try Kernel.metrics(of: Kernel.transform(block(), by: placement))

        #expect(approx(metrics.boundsMin, SIMD3(-1, -1, 3)))
        #expect(approx(metrics.boundsMax, SIMD3(1, 0, 7)))
    }

    @Test("A non-unit axis is normalised")
    func nonUnitAxis() throws {
        let metrics = try Kernel.metrics(
            of: Kernel.transform(block(), by: Placement(axis: SIMD3(0, 0, 7), angle: .pi / 2)))

        #expect(approx(metrics.boundsMax, SIMD3(2, 1, 1)))
    }

    @Test("A zero rotation axis is rejected")
    func zeroAxis() throws {
        #expect(throws: KernelError.invalidDimensions("rotation axis must not be zero")) {
            try Kernel.transform(block(), by: Placement(axis: .zero, angle: 1))
        }
    }

    @Test("Non-finite placement values are rejected")
    func nonFinite() throws {
        #expect(throws: KernelError.self) {
            try Kernel.transform(block(), by: Placement(translation: SIMD3(.nan, 0, 0)))
        }
        #expect(throws: KernelError.self) {
            try Kernel.transform(block(), by: Placement(angle: .infinity))
        }
    }

    @Test("Transforming leaves the input untouched")
    func inputUnchanged() throws {
        let original = try block()
        _ = try Kernel.transform(original, by: Placement(translation: SIMD3(5, 5, 5)))

        #expect(approx(try Kernel.metrics(of: original).boundsMin, SIMD3(-1, -2, 0)))
    }

    @Test("A placement survives a JSON round trip")
    func codable() throws {
        let placement = Placement(translation: SIMD3(1, 2, 3), axis: SIMD3(0, 1, 0), angle: 0.5)
        let decoded = try JSONDecoder().decode(Placement.self, from: JSONEncoder().encode(placement))

        #expect(decoded == placement)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `xcrun swift test --filter PlacementTests`; expected: `Placement` not found.

- [ ] **Step 3: Implement**

`Placement.swift`:

```swift
import simd

public struct Placement: Sendable, Hashable, Codable {
    public var translation: SIMD3<Double>
    public var axis: SIMD3<Double>
    public var angle: Double

    public init(translation: SIMD3<Double> = .zero, axis: SIMD3<Double> = SIMD3(0, 0, 1), angle: Double = 0) {
        self.translation = translation
        self.axis = axis
        self.angle = angle
    }

    public static let identity = Placement()

    var rotation: simd_double3x3 {
        simd_double3x3(simd_quatd(angle: angle, axis: simd_normalize(axis)))
    }
}
```

`Kernel+Transform.swift`:

```swift
import OCCTSwift
import simd

extension Kernel {
    public static func transform(_ solid: Solid, by placement: Placement) throws -> Solid {
        try validate(placement)
        return try OCCTSerial.withLock { Solid(shape: try placed(solid.shape, placement)) }
    }

    static func validate(_ placement: Placement) throws {
        let values = [placement.translation, placement.axis].flatMap { [$0.x, $0.y, $0.z] } + [placement.angle]
        guard values.allSatisfy(\.isFinite) else {
            throw KernelError.invalidDimensions("placement values must be finite")
        }
        guard simd_length(placement.axis) > 0 else {
            throw KernelError.invalidDimensions("rotation axis must not be zero")
        }
    }

    static func placed(_ shape: Shape, _ placement: Placement) throws -> Shape {
        let r = placement.rotation
        let t = placement.translation
        guard
            let matrix = Matrix12Grouped([
                r[0][0], r[1][0], r[2][0],
                r[0][1], r[1][1], r[2][1],
                r[0][2], r[1][2], r[2][2],
                t.x, t.y, t.z,
            ]),
            let moved = shape.transformed(matrix: matrix)
        else {
            throw KernelError.operationFailed("apply the placement")
        }
        return moved
    }
}
```

(`simd_double3x3` is column-major, `r[column][row]`; `Matrix12Grouped` wants row-major rotation rows followed by the translation.)

- [ ] **Step 4: Run all package tests** — expected all pass.
- [ ] **Step 5: Commit** — `feat(kernel): transform solids by a placement`

### Task 3: Placed primitive solids

**Files:**

- Create: `Sources/CADKernel/Kernel+Primitives.swift`
- Test: `Tests/CADKernelTests/PrimitiveTests.swift`

**Interfaces:**

- Consumes: `Placement`, `Kernel.validate(_:)`, `Kernel.placed(_:_:)`.
- Produces:
  - `public static func box(width: Double, depth: Double, height: Double, placement: Placement = .identity) throws -> Solid`
  - `public static func cylinder(radius: Double, height: Double, placement: Placement = .identity) throws -> Solid`
  - `public static func sphere(radius: Double, placement: Placement = .identity) throws -> Solid`
  - `public static func cone(bottomRadius: Double, topRadius: Double, height: Double, placement: Placement = .identity) throws -> Solid`
  - `public static func torus(majorRadius: Double, minorRadius: Double, placement: Placement = .identity) throws -> Solid`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import CADKernel

@Suite("Primitive solids")
struct PrimitiveTests {
    private func expectClosed(_ metrics: SolidMetrics) {
        #expect(metrics.isValid)
        #expect(metrics.isClosed)
        #expect(metrics.solidCount == 1)
    }

    @Test("A box sits with its corner on the origin")
    func box() throws {
        let metrics = try Kernel.metrics(of: Kernel.box(width: 2, depth: 3, height: 4))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 24))
        #expect(approx(metrics.boundsMin, .zero))
        #expect(approx(metrics.boundsMax, SIMD3(2, 3, 4)))
        #expect(metrics.faceCount == 6)
        #expect(metrics.edgeCount == 12)
    }

    @Test("A cylinder stands on the XY plane along +Z")
    func cylinder() throws {
        let metrics = try Kernel.metrics(of: Kernel.cylinder(radius: 1, height: 2))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 2 * .pi))
        #expect(approx(metrics.boundsMin, SIMD3(-1, -1, 0), tolerance: 1e-4))
        #expect(approx(metrics.boundsMax, SIMD3(1, 1, 2), tolerance: 1e-4))
        #expect(metrics.faceCount == 3)
    }

    @Test("A sphere is centred on the origin")
    func sphere() throws {
        let metrics = try Kernel.metrics(of: Kernel.sphere(radius: 2))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 32 * .pi / 3))
        #expect(approx(metrics.boundsMin, SIMD3(-2, -2, -2), tolerance: 1e-4))
        #expect(approx(metrics.boundsMax, SIMD3(2, 2, 2), tolerance: 1e-4))
    }

    @Test("A cone frustum has the analytic volume")
    func frustum() throws {
        let metrics = try Kernel.metrics(of: Kernel.cone(bottomRadius: 2, topRadius: 1, height: 3))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 7 * .pi))
        #expect(approx(metrics.boundsMax.z, 3))
    }

    @Test("A cone may come to a point")
    func pointedCone() throws {
        let metrics = try Kernel.metrics(of: Kernel.cone(bottomRadius: 2, topRadius: 0, height: 3))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 4 * .pi))
        #expect(metrics.faceCount == 2)
    }

    @Test("A torus lies in the XY plane around the origin")
    func torus() throws {
        let metrics = try Kernel.metrics(of: Kernel.torus(majorRadius: 3, minorRadius: 1))

        expectClosed(metrics)
        #expect(approx(metrics.volume, 6 * .pi * .pi))
        #expect(approx(metrics.boundsMin, SIMD3(-4, -4, -1), tolerance: 1e-4))
        #expect(approx(metrics.boundsMax, SIMD3(4, 4, 1), tolerance: 1e-4))
    }

    @Test("A placement positions the primitive")
    func placed() throws {
        let placement = Placement(translation: SIMD3(0, 0, 5), axis: SIMD3(1, 0, 0), angle: .pi / 2)
        let metrics = try Kernel.metrics(of: Kernel.cylinder(radius: 1, height: 2, placement: placement))

        #expect(approx(metrics.volume, 2 * .pi))
        #expect(approx(metrics.boundsMin, SIMD3(-1, -2, 4), tolerance: 1e-4))
        #expect(approx(metrics.boundsMax, SIMD3(1, 0, 6), tolerance: 1e-4))
    }

    @Test("Non-positive sizes are rejected", arguments: [0.0, -1.0])
    func rejectsNonPositive(value: Double) {
        #expect(throws: KernelError.self) { try Kernel.box(width: value, depth: 1, height: 1) }
        #expect(throws: KernelError.self) { try Kernel.cylinder(radius: value, height: 1) }
        #expect(throws: KernelError.self) { try Kernel.sphere(radius: value) }
        #expect(throws: KernelError.self) { try Kernel.cone(bottomRadius: 1, topRadius: 0, height: value) }
        #expect(throws: KernelError.self) { try Kernel.torus(majorRadius: 2, minorRadius: value) }
    }

    @Test("Non-finite sizes are rejected", arguments: [Double.nan, .infinity])
    func rejectsNonFinite(value: Double) {
        #expect(throws: KernelError.self) { try Kernel.box(width: 1, depth: value, height: 1) }
        #expect(throws: KernelError.self) { try Kernel.sphere(radius: value) }
        #expect(throws: KernelError.self) { try Kernel.cone(bottomRadius: value, topRadius: 0, height: 1) }
    }

    @Test("Degenerate cones are rejected", arguments: [(1.0, 1.0), (0.0, 0.0), (-1.0, 1.0)])
    func rejectsDegenerateCone(bottom: Double, top: Double) {
        #expect(throws: KernelError.self) { try Kernel.cone(bottomRadius: bottom, topRadius: top, height: 1) }
    }

    @Test("A torus whose tube reaches the axis is rejected", arguments: [2.0, 3.0])
    func rejectsSelfIntersectingTorus(minor: Double) {
        #expect(throws: KernelError.self) { try Kernel.torus(majorRadius: 2, minorRadius: minor) }
    }

    @Test("A bad placement is rejected")
    func rejectsBadPlacement() {
        #expect(throws: KernelError.invalidDimensions("rotation axis must not be zero")) {
            try Kernel.sphere(radius: 1, placement: Placement(axis: .zero))
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `xcrun swift test --filter PrimitiveTests`; expected: `Kernel.box` not found.

- [ ] **Step 3: Implement**

```swift
import OCCTSwift

extension Kernel {
    public static func box(width: Double, depth: Double, height: Double, placement: Placement = .identity) throws -> Solid {
        try requirePositive(["width": width, "depth": depth, "height": height])
        return try primitive("box", placement) { Shape.box(origin: .zero, width: width, height: depth, depth: height) }
    }

    public static func cylinder(radius: Double, height: Double, placement: Placement = .identity) throws -> Solid {
        try requirePositive(["radius": radius, "height": height])
        return try primitive("cylinder", placement) { Shape.cylinder(radius: radius, height: height) }
    }

    public static func sphere(radius: Double, placement: Placement = .identity) throws -> Solid {
        try requirePositive(["radius": radius])
        return try primitive("sphere", placement) { Shape.sphere(radius: radius) }
    }

    public static func cone(
        bottomRadius: Double, topRadius: Double, height: Double, placement: Placement = .identity
    ) throws -> Solid {
        try requirePositive(["height": height])
        guard bottomRadius.isFinite, topRadius.isFinite, bottomRadius >= 0, topRadius >= 0 else {
            throw KernelError.invalidDimensions("cone radii must be finite and not negative")
        }
        guard bottomRadius != topRadius else {
            throw KernelError.invalidDimensions("cone radii must differ; use a cylinder for equal radii")
        }
        return try primitive("cone", placement) {
            Shape.cone(bottomRadius: bottomRadius, topRadius: topRadius, height: height)
        }
    }

    public static func torus(majorRadius: Double, minorRadius: Double, placement: Placement = .identity) throws -> Solid {
        try requirePositive(["majorRadius": majorRadius, "minorRadius": minorRadius])
        guard minorRadius < majorRadius else {
            throw KernelError.invalidDimensions("minorRadius must be smaller than majorRadius")
        }
        return try primitive("torus", placement) { Shape.torus(majorRadius: majorRadius, minorRadius: minorRadius) }
    }

    private static func requirePositive(_ values: KeyValuePairs<String, Double>) throws {
        for (name, value) in values where !(value.isFinite && value > 0) {
            throw KernelError.invalidDimensions("\(name) must be a finite number greater than 0")
        }
    }

    private static func primitive(_ name: String, _ placement: Placement, make: () -> Shape?) throws -> Solid {
        try validate(placement)
        return try OCCTSerial.withLock {
            guard let shape = make(), shape.isValid else {
                throw KernelError.operationFailed("create the \(name)")
            }
            return Solid(shape: try placed(shape, placement))
        }
    }
}
```

(`requirePositive` takes `KeyValuePairs` so the first failing argument is reported deterministically; `-1` for the cone check means a negative radius is also caught.)

- [ ] **Step 4: Run all package tests** — expected all pass.
- [ ] **Step 5: Commit** — `feat(kernel): create placed primitive solids`

### Task 4: Booleans

**Files:**

- Create: `Sources/CADKernel/Kernel+Booleans.swift`
- Test: `Tests/CADKernelTests/BooleanTests.swift`

**Interfaces:**

- Consumes: primitives, `Placement`, `KernelError.emptyResult`.
- Produces:
  - `public enum BooleanOperation: String, Sendable, Hashable, Codable, CaseIterable { case union, subtract, intersect }`
  - `public static func boolean(_ operation: BooleanOperation, _ target: Solid, _ tool: Solid) throws -> Solid`
  - `public static func solids(of solid: Solid) -> [Solid]`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import CADKernel

@Suite("Booleans")
struct BooleanTests {
    @Test("Drilling a through hole removes exactly the cylinder's volume")
    func drill() throws {
        let plate = try Kernel.box(width: 4, depth: 4, height: 2)
        let drill = try Kernel.cylinder(radius: 1, height: 4, placement: Placement(translation: SIMD3(2, 2, -1)))
        let metrics = try Kernel.metrics(of: Kernel.boolean(.subtract, plate, drill))

        #expect(approx(metrics.volume, 32 - 2 * .pi))
        #expect(metrics.isClosed)
        #expect(metrics.solidCount == 1)
        #expect(metrics.faceCount == 7)
    }

    @Test("Uniting overlapping boxes counts the overlap once")
    func union() throws {
        let a = try Kernel.box(width: 2, depth: 2, height: 2)
        let b = try Kernel.box(width: 2, depth: 2, height: 2, placement: Placement(translation: SIMD3(1, 0, 0)))
        let metrics = try Kernel.metrics(of: Kernel.boolean(.union, a, b))

        #expect(approx(metrics.volume, 12))
        #expect(metrics.solidCount == 1)
        #expect(metrics.isClosed)
        #expect(approx(metrics.boundsMax, SIMD3(3, 2, 2)))
    }

    @Test("Intersecting a sphere with a slab above XY leaves a hemisphere")
    func intersect() throws {
        let ball = try Kernel.sphere(radius: 1)
        let slab = try Kernel.box(width: 4, depth: 4, height: 2, placement: Placement(translation: SIMD3(-2, -2, 0)))
        let metrics = try Kernel.metrics(of: Kernel.boolean(.intersect, ball, slab))

        #expect(approx(metrics.volume, 2 * .pi / 3))
        #expect(metrics.isClosed)
    }

    @Test("Uniting disjoint solids keeps both as separate solids")
    func disjointUnion() throws {
        let a = try Kernel.box(width: 1, depth: 1, height: 1)
        let b = try Kernel.box(width: 2, depth: 1, height: 1, placement: Placement(translation: SIMD3(5, 0, 0)))
        let united = try Kernel.boolean(.union, a, b)

        #expect(try Kernel.metrics(of: united).solidCount == 2)
        let volumes = try Kernel.solids(of: united).map { try Kernel.metrics(of: $0).volume }.sorted()
        #expect(volumes.count == 2)
        #expect(approx(volumes[0], 1) && approx(volumes[1], 2))
    }

    @Test("Intersecting disjoint solids leaves nothing")
    func emptyIntersection() throws {
        let a = try Kernel.box(width: 1, depth: 1, height: 1)
        let b = try Kernel.box(width: 1, depth: 1, height: 1, placement: Placement(translation: SIMD3(5, 0, 0)))

        #expect(throws: KernelError.emptyResult) { try Kernel.boolean(.intersect, a, b) }
    }

    @Test("Subtracting an enclosing tool leaves nothing")
    func emptySubtraction() throws {
        let small = try Kernel.box(width: 1, depth: 1, height: 1)
        let big = try Kernel.box(width: 3, depth: 3, height: 3, placement: Placement(translation: SIMD3(-1, -1, -1)))

        #expect(throws: KernelError.emptyResult) { try Kernel.boolean(.subtract, small, big) }
    }

    @Test("Booleans leave their inputs untouched")
    func inputsUnchanged() throws {
        let plate = try Kernel.box(width: 4, depth: 4, height: 2)
        let drill = try Kernel.cylinder(radius: 1, height: 4, placement: Placement(translation: SIMD3(2, 2, -1)))
        _ = try Kernel.boolean(.subtract, plate, drill)

        #expect(approx(try Kernel.metrics(of: plate).volume, 32))
        #expect(approx(try Kernel.metrics(of: drill).volume, 4 * .pi))
    }

    @Test("A single solid splits into itself")
    func splitSingle() throws {
        #expect(Kernel.solids(of: try Kernel.sphere(radius: 1)).count == 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `xcrun swift test --filter BooleanTests`; expected: `boolean` not found.

- [ ] **Step 3: Implement**

```swift
import OCCTSwift

public enum BooleanOperation: String, Sendable, Hashable, Codable, CaseIterable {
    case union, subtract, intersect
}

extension Kernel {
    public static func boolean(_ operation: BooleanOperation, _ target: Solid, _ tool: Solid) throws -> Solid {
        try OCCTSerial.withLock {
            let result: Shape? =
                switch operation {
                case .union: target.shape.union(tool.shape)
                case .subtract: target.shape.subtracting(tool.shape)
                case .intersect: target.shape.intersection(tool.shape)
                }
            guard let result, result.isValid else {
                throw KernelError.operationFailed("\(operation.rawValue) the solids")
            }
            guard result.solidCount > 0 else { throw KernelError.emptyResult }
            return Solid(shape: result)
        }
    }

    public static func solids(of solid: Solid) -> [Solid] {
        OCCTSerial.withLock { solid.shape.solids.map(Solid.init(shape:)) }
    }
}
```

- [ ] **Step 4: Run all package tests** — expected all pass.
- [ ] **Step 5: Commit** — `feat(kernel): combine solids with booleans`

### Task 5: Concurrent use from background tasks

**Files:**

- Test: `Tests/CADKernelTests/ConcurrencyTests.swift`

**Interfaces:**

- Consumes: `box`, `cylinder`, `boolean`, `metrics`, `tessellate`.

- [ ] **Step 1: Write the test**

```swift
import Foundation
import Testing
@testable import CADKernel

@Suite("Concurrency")
struct ConcurrencyTests {
    private static func drilledPlate(width: Double) throws -> (volume: Double, triangles: Int) {
        let plate = try Kernel.box(width: width, depth: 2, height: 2)
        let drill = try Kernel.cylinder(
            radius: 0.5, height: 4, placement: Placement(translation: SIMD3(width / 2, 1, -1)))
        let drilled = try Kernel.boolean(.subtract, plate, drill)
        return (try Kernel.metrics(of: drilled).volume, try Kernel.tessellate(drilled).indices.count / 3)
    }

    @Test("Kernel operations from many tasks at once give the serial results")
    func parallelOperations() async throws {
        let widths = (1...16).map { 1.0 + Double($0) / 4 }
        let results = try await withThrowingTaskGroup(of: (Double, Double, Int).self) { group in
            for width in widths {
                group.addTask {
                    let result = try Self.drilledPlate(width: width)
                    return (width, result.volume, result.triangles)
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(results.count == widths.count)
        for (width, volume, triangles) in results {
            #expect(approx(volume, 4 * width - .pi / 2), "width \(width)")
            #expect(triangles > 0)
        }
    }
}
```

The test passes if the lock discipline holds (it is a guard, not a red-first test: existing code already takes the lock). Run it several times: `xcrun swift test --filter ConcurrencyTests` ×3.

- [ ] **Step 2: Run all package tests** — expected all pass.
- [ ] **Step 3: Commit** — `test(kernel): exercise kernel operations from concurrent tasks`

### Task 6: Verify the app still builds

- [ ] `xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test > build.log 2>&1; tail -30 build.log` (log in the scratchpad). The app uses only `extrudeRectangle`, `fillet`, `tessellate`, `metrics`; `SolidMetrics` has no public initializer, so adding fields cannot break a call site.
