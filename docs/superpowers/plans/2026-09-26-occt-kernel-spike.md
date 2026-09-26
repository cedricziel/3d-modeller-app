# OCCT Kernel Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove OpenCASCADE works in the app end to end: the assistant creates a rectangular block with filleted vertical edges, it renders in the RealityKit viewport, survives save/reopen and undo. Along the way, measure the size and build-time cost.

**Architecture:** A new local package `Packages/CADKernel` is the only code that imports OCCTSwift. It exposes a tiny API (`Kernel.extrudeRectangle`, `Kernel.fillet`, `Kernel.tessellate`, `Kernel.metrics`) over opaque `Solid` values and returns plain triangle data (`KernelMesh`). The app converts `KernelMesh` into a RealityKit `MeshResource`, stores the block's parameters (`SolidRecipe`) on the entity and in the `.scene3d` file, and rebuilds the mesh from them on load, undo and duplicate.

**Tech Stack:** Swift 6, SwiftPM, XcodeGen, RealityKit, Swift Testing, OCCTSwift 3.0.0 (OCCT 8.0.1).

**Spec:** `docs/superpowers/specs/2026-09-26-geometry-kernel.md`

## Global Constraints

- Always run `xcrun swift …`, never bare `swift …` (the `swift` on `$PATH` doesn't match the Xcode SDK).
- OCCTSwift is pinned with `exact: "3.0.0"`. Never `from:` or a branch.
- Only `Packages/CADKernel` may `import OCCTSwift`. The app imports `CADKernel` only.
- Every OCCTSwift call runs inside `OCCTSerial.withLock { }`.
- Kernel failures surface as `KernelError`, never a crash or a silent `nil`.
- macOS 26.0 deployment target, Swift 6 strict concurrency, tools version 6.1 for the new package (OCCTSwift requires it).
- After editing `project.yml`, run `xcodegen generate`. The `.xcodeproj` is generated; commit it only if it's already tracked (`git ls-files 3DModellerApp.xcodeproj | head -1`).
- App tests: `xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test`. Package tests: `cd Packages/CADKernel && xcrun swift test`.
- Semantic commits, one concern each, no "and" in the subject. No code comments unless they explain something non-obvious.
- Units: scene units are meters, passed straight through to the kernel as `Double`. CAD geometry is Z-up; RealityKit is Y-up.

## Review Focus

1. **Fillet radius too large for the block** (e.g. radius ≥ half the width). Expected: the tool reports a readable failure and the scene is unchanged, with no crash and no half-added entity. Tests: Task 2 (kernel), Task 5 (scene unchanged), Task 6 (tool message).
2. **Zero or negative dimensions** from the assistant. Expected: a clear error before OCCT is called. Tests: Task 1, Task 6.
3. **Save and reopen a scene containing a block.** Expected: the block comes back with the same dimensions and fillet, not as a default box. Test: Task 5.
4. **Undo/redo around a block, and duplicating a block.** Expected: it's rebuilt from its recipe, not replaced by a box. Test: Task 5.
5. **Opening an existing `.scene3d` written before this change** (no `solid` key). Expected: it opens exactly as before. Test: Task 5.

---

### Task 1: CADKernel package with rectangle extrusion

Measures the baseline app size first, because it has to happen before OCCTSwift is added anywhere.

**Files:**

- Create: `Packages/CADKernel/Package.swift`
- Create: `Packages/CADKernel/Sources/CADKernel/Kernel.swift`
- Create: `Packages/CADKernel/Sources/CADKernel/Solid.swift`
- Create: `Packages/CADKernel/Tests/CADKernelTests/ExtrudeTests.swift`
- Create: `docs/spikes/2026-09-26-occt-kernel.md`

**Interfaces:**

- Consumes: nothing.
- Produces:
  - `public struct Solid: @unchecked Sendable` (opaque; internal `let shape: OCCTSwift.Shape`)
  - `public struct SolidMetrics: Sendable, Equatable { volume: Double; boundsMin: SIMD3<Double>; boundsMax: SIMD3<Double>; edgeCount: Int; isValid: Bool }`
  - `public enum KernelError: Error, Equatable, CustomStringConvertible { case invalidDimensions(String), operationFailed(String), noEdgesMatched }`
  - `public enum Kernel { static func extrudeRectangle(width: Double, height: Double, depth: Double) throws -> Solid; static func metrics(of: Solid) throws -> SolidMetrics }`

- [ ] **Step 1: Record the baseline Release size**

```bash
SPIKE="${TMPDIR}occt-spike"; mkdir -p "$SPIKE"
xcodegen generate
/usr/bin/time -p xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp -configuration Release \
  -derivedDataPath "$SPIKE/dd-baseline" build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4
APP="$SPIKE/dd-baseline/Build/Products/Release/3D Modeller.app"
du -sk "$APP"; stat -f%z "$APP/Contents/MacOS/3D Modeller"
```

Expected: `** BUILD SUCCEEDED **`, then two numbers (bundle KB, executable bytes) and the `real` build seconds.

- [ ] **Step 2: Start the findings doc with the baseline numbers**

Create `docs/spikes/2026-09-26-occt-kernel.md`, filling in the numbers from Step 1:

```markdown
# OCCT kernel spike: findings

Spec: `docs/superpowers/specs/2026-09-26-geometry-kernel.md`

## Size and build time (Release, arm64, CODE_SIGNING_ALLOWED=NO)

|                                                   | Baseline      | With CADKernel |
| ------------------------------------------------- | ------------- | -------------- |
| App bundle (`du -sk`, KB)                         | <from step 1> |                |
| Executable (bytes)                                | <from step 1> |                |
| Clean build (s)                                   | <from step 1> |                |
| Incremental build after touching one app file (s) |               |                |
```

- [ ] **Step 3: Create the package manifest**

`Packages/CADKernel/Package.swift`:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CADKernel",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0")
    ],
    products: [
        .library(name: "CADKernel", targets: ["CADKernel"])
    ],
    dependencies: [
        .package(url: "https://github.com/SecondMouseAU/OCCTSwift.git", exact: "3.0.0")
    ],
    targets: [
        .target(
            name: "CADKernel",
            dependencies: [.product(name: "OCCTSwift", package: "OCCTSwift")]
        ),
        .testTarget(
            name: "CADKernelTests",
            dependencies: ["CADKernel"]
        )
    ]
)
```

- [ ] **Step 4: Write the failing tests**

`Packages/CADKernel/Tests/CADKernelTests/ExtrudeTests.swift`:

```swift
import Testing
@testable import CADKernel

@Suite("Rectangle extrusion")
struct ExtrudeTests {
    @Test("Extruding a 2×1 rectangle by 0.5 gives a valid box of volume 1")
    func extrudesBox() throws {
        let solid = try Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5)
        let metrics = try Kernel.metrics(of: solid)

        #expect(metrics.isValid)
        #expect(abs(metrics.volume - 1.0) < 1e-9)
        #expect(metrics.edgeCount == 12)
    }

    @Test("The profile is centred on the origin in XY and extruded along +Z")
    func placement() throws {
        let metrics = try Kernel.metrics(of: Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5))

        let tolerance = 1e-6
        #expect(abs(metrics.boundsMin.x - -1.0) < tolerance)
        #expect(abs(metrics.boundsMin.y - -0.5) < tolerance)
        #expect(abs(metrics.boundsMin.z - 0.0) < tolerance)
        #expect(abs(metrics.boundsMax.x - 1.0) < tolerance)
        #expect(abs(metrics.boundsMax.y - 0.5) < tolerance)
        #expect(abs(metrics.boundsMax.z - 0.5) < tolerance)
    }

    @Test("Non-positive dimensions are rejected", arguments: [
        (0.0, 1.0, 1.0), (1.0, -1.0, 1.0), (1.0, 1.0, 0.0)
    ])
    func rejectsNonPositive(width: Double, height: Double, depth: Double) {
        #expect(throws: KernelError.self) {
            try Kernel.extrudeRectangle(width: width, height: height, depth: depth)
        }
    }
}
```

OCCT bounding boxes can be enlarged by a tiny tolerance gap. If `placement` fails by less than `1e-4`, loosen `tolerance` to `1e-4` and note it in the findings doc; don't change the geometry.

- [ ] **Step 5: Run the tests to verify they fail**

Run: `cd Packages/CADKernel && xcrun swift test`
Expected: compile failure, `cannot find 'Kernel' in scope`. The first run also downloads the 142 MB `OCCT.xcframework.zip`; that's expected.

- [ ] **Step 6: Implement**

`Packages/CADKernel/Sources/CADKernel/Solid.swift`:

```swift
import OCCTSwift

public struct Solid: @unchecked Sendable {
    let shape: Shape
}

public struct SolidMetrics: Sendable, Equatable {
    public let volume: Double
    public let boundsMin: SIMD3<Double>
    public let boundsMax: SIMD3<Double>
    public let edgeCount: Int
    public let isValid: Bool
}

public enum KernelError: Error, Equatable, CustomStringConvertible {
    case invalidDimensions(String)
    case operationFailed(String)
    case noEdgesMatched

    public var description: String {
        switch self {
        case .invalidDimensions(let detail): "Invalid dimensions: \(detail)"
        case .operationFailed(let operation): "The geometry kernel could not \(operation)"
        case .noEdgesMatched: "No edges matched the selection"
        }
    }
}
```

`Packages/CADKernel/Sources/CADKernel/Kernel.swift`:

```swift
import OCCTSwift

public enum Kernel {
    public static func extrudeRectangle(width: Double, height: Double, depth: Double) throws -> Solid {
        guard width > 0, height > 0, depth > 0 else {
            throw KernelError.invalidDimensions("width, height and depth must be greater than 0")
        }
        return try OCCTSerial.withLock {
            guard let profile = Wire.rectangle(width: width, height: height),
                  let shape = Shape.extrude(profile: profile, direction: SIMD3(0, 0, 1), length: depth),
                  shape.isValid
            else {
                throw KernelError.operationFailed("extrude the rectangle")
            }
            return Solid(shape: shape)
        }
    }

    public static func metrics(of solid: Solid) throws -> SolidMetrics {
        try OCCTSerial.withLock {
            guard let volume = solid.shape.volume, let bounds = solid.shape.boundingBox else {
                throw KernelError.operationFailed("measure the solid")
            }
            return SolidMetrics(
                volume: volume,
                boundsMin: bounds.min,
                boundsMax: bounds.max,
                edgeCount: solid.shape.edgeCount,
                isValid: solid.shape.isValid
            )
        }
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd Packages/CADKernel && xcrun swift test`
Expected: all `ExtrudeTests` pass. Note the clean package build time in the findings doc under a "Notes" heading.

- [ ] **Step 8: Commit**

```bash
git add Packages/CADKernel docs/spikes/2026-09-26-occt-kernel.md
git commit -m "feat(kernel): add CADKernel package with rectangle extrusion"
```

---

### Task 2: Fillet edges selected by direction

**Files:**

- Create: `Packages/CADKernel/Sources/CADKernel/EdgeQuery.swift`
- Modify: `Packages/CADKernel/Sources/CADKernel/Kernel.swift`
- Test: `Packages/CADKernel/Tests/CADKernelTests/FilletTests.swift`

**Interfaces:**

- Consumes: `Solid`, `SolidMetrics`, `KernelError`, `Kernel.extrudeRectangle`, `Kernel.metrics` (Task 1).
- Produces:
  - `public enum EdgeQuery: Sendable, Equatable { case parallel(to: SIMD3<Double>) }`
  - `Kernel.fillet(_ solid: Solid, edges: EdgeQuery, radius: Double) throws -> Solid`

- [ ] **Step 1: Write the failing tests**

`Packages/CADKernel/Tests/CADKernelTests/FilletTests.swift`:

```swift
import Foundation
import Testing
@testable import CADKernel

@Suite("Edge fillets")
struct FilletTests {
    @Test("Filleting the four vertical edges removes exactly the corner material")
    func filletVerticalEdges() throws {
        let (width, height, depth, radius) = (2.0, 1.0, 0.5, 0.1)
        let block = try Kernel.extrudeRectangle(width: width, height: height, depth: depth)

        let rounded = try Kernel.fillet(block, edges: .parallel(to: SIMD3(0, 0, 1)), radius: radius)
        let metrics = try Kernel.metrics(of: rounded)

        let removedPerEdge = radius * radius * (1 - Double.pi / 4) * depth
        let expected = width * height * depth - 4 * removedPerEdge
        #expect(metrics.isValid)
        #expect(abs(metrics.volume - expected) < 1e-6)
        #expect(metrics.edgeCount > 12)
    }

    @Test("Filleting leaves the input solid untouched")
    func inputUnchanged() throws {
        let block = try Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5)
        _ = try Kernel.fillet(block, edges: .parallel(to: SIMD3(0, 0, 1)), radius: 0.1)

        #expect(abs(try Kernel.metrics(of: block).volume - 1.0) < 1e-9)
    }

    @Test("A radius larger than half the block's width fails with a kernel error")
    func radiusTooLarge() throws {
        let block = try Kernel.extrudeRectangle(width: 1, height: 1, depth: 1)

        #expect(throws: KernelError.self) {
            try Kernel.fillet(block, edges: .parallel(to: SIMD3(0, 0, 1)), radius: 0.8)
        }
    }

    @Test("Non-positive radius is rejected", arguments: [0.0, -0.1])
    func nonPositiveRadius(radius: Double) throws {
        let block = try Kernel.extrudeRectangle(width: 1, height: 1, depth: 1)

        #expect(throws: KernelError.invalidDimensions("radius must be greater than 0")) {
            try Kernel.fillet(block, edges: .parallel(to: SIMD3(0, 0, 1)), radius: radius)
        }
    }

    @Test("A direction no edge follows reports that nothing matched")
    func noMatch() throws {
        let block = try Kernel.extrudeRectangle(width: 1, height: 1, depth: 1)
        let diagonal = SIMD3<Double>(1, 1, 1) / sqrt(3)

        #expect(throws: KernelError.noEdgesMatched) {
            try Kernel.fillet(block, edges: .parallel(to: diagonal), radius: 0.1)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/CADKernel && xcrun swift test --filter FilletTests`
Expected: compile failure, `type 'Kernel' has no member 'fillet'`.

- [ ] **Step 3: Implement**

`Packages/CADKernel/Sources/CADKernel/EdgeQuery.swift`:

```swift
import OCCTSwift

public enum EdgeQuery: Sendable, Equatable {
    case parallel(to: SIMD3<Double>)

    func edges(of shape: Shape) -> [Edge] {
        switch self {
        case .parallel(let axis):
            shape.edges(parallelTo: axis)
        }
    }
}
```

Add to `Kernel` in `Kernel.swift`:

```swift
    public static func fillet(_ solid: Solid, edges query: EdgeQuery, radius: Double) throws -> Solid {
        guard radius > 0 else {
            throw KernelError.invalidDimensions("radius must be greater than 0")
        }
        return try OCCTSerial.withLock {
            let edges = query.edges(of: solid.shape)
            guard !edges.isEmpty else { throw KernelError.noEdgesMatched }
            guard let shape = solid.shape.filleted(edges: edges, radius: radius), shape.isValid else {
                throw KernelError.operationFailed("fillet the selected edges")
            }
            return Solid(shape: shape)
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/CADKernel && xcrun swift test`
Expected: all tests pass. If `radiusTooLarge` fails because OCCT returns a valid-looking shape, add a check in `fillet` that the result's volume is positive and smaller than the input's, and record the OCCT behaviour in the findings doc.

- [ ] **Step 5: Commit**

```bash
git add Packages/CADKernel
git commit -m "feat(kernel): fillet edges selected by direction"
```

---

### Task 3: Tessellation into plain triangle data

**Files:**

- Create: `Packages/CADKernel/Sources/CADKernel/KernelMesh.swift`
- Modify: `Packages/CADKernel/Sources/CADKernel/Kernel.swift`
- Test: `Packages/CADKernel/Tests/CADKernelTests/TessellateTests.swift`

**Interfaces:**

- Consumes: `Solid`, `Kernel.extrudeRectangle`, `Kernel.fillet`, `Kernel.metrics`, `EdgeQuery` (Tasks 1–2).
- Produces:
  - `public struct KernelMesh: Sendable, Equatable { positions: [SIMD3<Float>]; normals: [SIMD3<Float>]; indices: [UInt32] }`
  - `Kernel.tessellate(_ solid: Solid, tolerance: Double = 0.001) throws -> KernelMesh`

- [ ] **Step 1: Write the failing tests**

`Packages/CADKernel/Tests/CADKernelTests/TessellateTests.swift`:

```swift
import simd
import Testing
@testable import CADKernel

@Suite("Tessellation")
struct TessellateTests {
    private func roundedBlock() throws -> Solid {
        let block = try Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5)
        return try Kernel.fillet(block, edges: .parallel(to: SIMD3(0, 0, 1)), radius: 0.1)
    }

    @Test("The mesh is a well-formed triangle list")
    func wellFormed() throws {
        let mesh = try Kernel.tessellate(roundedBlock())

        #expect(!mesh.positions.isEmpty)
        #expect(mesh.normals.count == mesh.positions.count)
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
    }

    @Test("Every vertex lies inside the solid's bounds")
    func insideBounds() throws {
        let solid = try roundedBlock()
        let metrics = try Kernel.metrics(of: solid)
        let mesh = try Kernel.tessellate(solid)

        let lower = SIMD3<Float>(metrics.boundsMin) - 1e-4
        let upper = SIMD3<Float>(metrics.boundsMax) + 1e-4
        #expect(mesh.positions.allSatisfy { all($0 .>= lower) && all($0 .<= upper) })
    }

    @Test("Triangles wind counter-clockwise when seen from outside")
    func outwardWinding() throws {
        let mesh = try Kernel.tessellate(roundedBlock())

        for start in stride(from: 0, to: mesh.indices.count, by: 3) {
            let (i0, i1, i2) = (Int(mesh.indices[start]), Int(mesh.indices[start + 1]), Int(mesh.indices[start + 2]))
            let (a, b, c) = (mesh.positions[i0], mesh.positions[i1], mesh.positions[i2])
            let faceNormal = simd_cross(b - a, c - a)
            let vertexNormal = mesh.normals[i0] + mesh.normals[i1] + mesh.normals[i2]
            #expect(simd_dot(faceNormal, vertexNormal) > 0, "triangle at index \(start) winds inward")
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/CADKernel && xcrun swift test --filter TessellateTests`
Expected: compile failure, `type 'Kernel' has no member 'tessellate'`.

- [ ] **Step 3: Implement**

`Packages/CADKernel/Sources/CADKernel/KernelMesh.swift`:

```swift
public struct KernelMesh: Sendable, Equatable {
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let indices: [UInt32]
}
```

Add to `Kernel`:

```swift
    public static func tessellate(_ solid: Solid, tolerance: Double = 0.001) throws -> KernelMesh {
        try OCCTSerial.withLock {
            guard let mesh = solid.shape.mesh(linearDeflection: tolerance, angularDeflection: 0.5) else {
                throw KernelError.operationFailed("tessellate the solid")
            }
            return KernelMesh(positions: mesh.vertices, normals: mesh.normals, indices: mesh.indices)
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/CADKernel && xcrun swift test`
Expected: all pass. If `outwardWinding` fails on every triangle, OCCTSwift winds clockwise: reverse each triangle's index order in `tessellate` (swap the 2nd and 3rd index of each triple) and record that in the findings doc. If it fails on only some triangles, stop and report; that's an orientation bug upstream, not something to paper over.

- [ ] **Step 5: Commit**

```bash
git add Packages/CADKernel
git commit -m "feat(kernel): tessellate solids into triangle meshes"
```

---

### Task 4: Wire CADKernel into the app with a RealityKit mesh conversion

**Files:**

- Modify: `project.yml` (the `packages:` block, and `targets.3DModellerApp.dependencies`)
- Modify: `Package.swift` (root)
- Create: `3DModellerApp/Scene/KernelMesh+RealityKit.swift`
- Test: `3DModellerAppTests/KernelMeshRealityKitTests.swift`

**Interfaces:**

- Consumes: `KernelMesh`, `Kernel.*` (Tasks 1–3).
- Produces: `extension KernelMesh { var meshDescriptor: MeshDescriptor }` (internal to the app target).

- [ ] **Step 1: Add the package to the build**

In `project.yml`, add under `packages:`:

```yaml
CADKernel:
  path: Packages/CADKernel
```

and under `targets.3DModellerApp.dependencies:`:

```yaml
- package: CADKernel
  product: CADKernel
```

In the root `Package.swift`, add `.package(path: "Packages/CADKernel")` to `dependencies` and `"CADKernel"` to the executable target's `dependencies`.

Run: `xcodegen generate`

- [ ] **Step 2: Write the failing test**

`3DModellerAppTests/KernelMeshRealityKitTests.swift`:

```swift
import CADKernel
import RealityKit
import Testing
@testable import _D_Modeller

@Suite("KernelMesh → RealityKit")
@MainActor
struct KernelMeshRealityKitTests {
    @Test("A tessellated block becomes a MeshResource with the block's extents")
    func convertsToMeshResource() throws {
        let block = try Kernel.extrudeRectangle(width: 2, height: 1, depth: 0.5)
        let kernelMesh = try Kernel.tessellate(block)

        let resource = try MeshResource.generate(from: [kernelMesh.meshDescriptor])

        let extents = resource.bounds.extents
        #expect(abs(extents.x - 2) < 1e-3)
        #expect(abs(extents.y - 1) < 1e-3)
        #expect(abs(extents.z - 0.5) < 1e-3)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test -only-testing:3DModellerAppTests/KernelMeshRealityKitTests 2>&1 | tail -20`
Expected: compile failure, `value of type 'KernelMesh' has no member 'meshDescriptor'`.

- [ ] **Step 4: Implement**

`3DModellerApp/Scene/KernelMesh+RealityKit.swift`:

```swift
import CADKernel
import RealityKit

extension KernelMesh {
    var meshDescriptor: MeshDescriptor {
        var descriptor = MeshDescriptor(name: "solid")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return descriptor
    }
}
```

- [ ] **Step 5: Run the full app test suite**

Run: `xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, including the existing tests.

- [ ] **Step 6: Commit**

```bash
git add project.yml Package.swift 3DModellerApp/Scene/KernelMesh+RealityKit.swift 3DModellerAppTests/KernelMeshRealityKitTests.swift
git ls-files --error-unmatch 3DModellerApp.xcodeproj/project.pbxproj >/dev/null 2>&1 && git add 3DModellerApp.xcodeproj
git commit -m "feat(app): render kernel meshes with RealityKit"
```

---

### Task 5: Blocks as scene entities that survive save, undo and duplicate

**Files:**

- Modify: `3DModellerApp/Scene/SceneDocument.swift` (`EntityData`, `EntityType`; add `SolidRecipe`)
- Modify: `3DModellerApp/Scene/SceneManager.swift` (`createPrimitive` material code, `duplicateEntity`, `restoreSnapshot`, `toSceneData`, `loadSceneData`, `CADEntity`)
- Test: `3DModellerAppTests/SolidEntityTests.swift`

**Interfaces:**

- Consumes: `Kernel.extrudeRectangle`, `Kernel.fillet`, `Kernel.tessellate`, `EdgeQuery`, `KernelError` (Tasks 1–3), `KernelMesh.meshDescriptor` (Task 4).
- Produces:
  - `struct SolidRecipe: Codable, Equatable { var width: Double; var height: Double; var depth: Double; var filletRadius: Double? }`
  - `EntityData.EntityType.solid`
  - `EntityData.solid: SolidRecipe?` (new init parameter `solid: SolidRecipe? = nil`, last)
  - `CADEntity.solid: SolidRecipe?` (new init parameter `solid: SolidRecipe? = nil`, last)
  - `SceneManager.createSolid(recipe: SolidRecipe, name: String? = nil, position: SIMD3<Float> = .zero, color: ColorData = ColorData(r: 0.8, g: 0.8, b: 0.8)) throws -> CADEntity`

- [ ] **Step 1: Write the failing tests**

`3DModellerAppTests/SolidEntityTests.swift`:

```swift
import CADKernel
import Foundation
import RealityKit
import Testing
@testable import _D_Modeller

@Suite("Solid entities")
@MainActor
struct SolidEntityTests {
    let recipe = SolidRecipe(width: 0.4, height: 0.2, depth: 0.1, filletRadius: 0.02)

    @Test("createSolid adds a selectable entity with the recipe")
    func createsEntity() throws {
        let scene = SceneManager()

        let entity = try scene.createSolid(recipe: recipe, name: "Bracket")

        #expect(scene.entities.count == 1)
        #expect(entity.type == .solid)
        #expect(entity.solid == recipe)
        #expect(entity.name == "Bracket")
    }

    @Test("A fillet that doesn't fit throws and leaves the scene unchanged")
    func failedFilletLeavesSceneAlone() throws {
        let scene = SceneManager()
        let impossible = SolidRecipe(width: 0.1, height: 0.1, depth: 0.1, filletRadius: 0.08)

        #expect(throws: KernelError.self) { try scene.createSolid(recipe: impossible) }
        #expect(scene.entities.isEmpty)
        #expect(scene.rootEntity.children.count == SceneManager().rootEntity.children.count)
    }

    @Test("Saving and loading keeps the block's recipe")
    func roundTrip() throws {
        let scene = SceneManager()
        _ = try scene.createSolid(recipe: recipe, name: "Bracket")

        let encoded = try JSONEncoder().encode(scene.toSceneData())
        let reloaded = SceneManager()
        reloaded.loadSceneData(try JSONDecoder().decode(SceneData.self, from: encoded))

        let entity = try #require(reloaded.entity(named: "Bracket"))
        #expect(entity.type == .solid)
        #expect(entity.solid == recipe)
    }

    @Test("Scene files written before solids existed still load")
    func legacyFile() throws {
        let legacy = """
        {"entities":[{"id":"6F1B3C2E-1111-4A6B-9C1D-2E3F4A5B6C7D","name":"OldBox","type":"box",
        "transform":{"position":[0,0,0],"rotation":[0,0,0],"scale":[1,1,1]},
        "material":{"color":{"r":0.8,"g":0.8,"b":0.8,"a":1},"metallic":0,"roughness":0.5},
        "isVisible":true}],
        "metadata":{"name":"Old","createdAt":0,"modifiedAt":0}}
        """
        let data = try JSONDecoder().decode(SceneData.self, from: Data(legacy.utf8))

        #expect(data.entities.first?.type == .box)
        #expect(data.entities.first?.solid == nil)
    }

    @Test("Undo after deleting a block brings back a block, not a box")
    func undoRestoresSolid() throws {
        let scene = SceneManager()
        let entity = try scene.createSolid(recipe: recipe, name: "Bracket")
        _ = scene.deleteEntity(id: entity.id)

        scene.undo()

        let restored = try #require(scene.entities.values.first { $0.name == "Bracket" })
        #expect(restored.type == .solid)
        #expect(restored.solid == recipe)
    }

    @Test("Duplicating a block copies its recipe")
    func duplicate() throws {
        let scene = SceneManager()
        let entity = try scene.createSolid(recipe: recipe, name: "Bracket")

        let copy = try #require(scene.duplicateEntity(id: entity.id))

        #expect(copy.type == .solid)
        #expect(copy.solid == recipe)
    }
}
```

Before writing `legacyFile`, confirm the JSON matches what the current `SceneDocument` encodes: run `SceneDocumentTests` once and, if needed, adjust the literal to the encoder's actual shape for `SIMD3<Float>` and `Date`. The point of the test is only that a document without a `solid` key decodes.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test -only-testing:3DModellerAppTests/SolidEntityTests 2>&1 | tail -20`
Expected: compile failure, `cannot find 'SolidRecipe' in scope`.

- [ ] **Step 3: Add the data model**

In `SceneDocument.swift`:

- Add `case solid` to `EntityData.EntityType`.
- Add `var solid: SolidRecipe?` to `EntityData`, plus an init parameter `solid: SolidRecipe? = nil` (last), assigned in the init. Synthesized `Codable` decodes a missing optional key as `nil`, which is what `legacyFile` checks.
- Add after `EntityData`:

```swift
struct SolidRecipe: Codable, Equatable {
    var width: Double
    var height: Double
    var depth: Double
    var filletRadius: Double?
}
```

In `SceneManager.swift`, give `CADEntity` a `let solid: SolidRecipe?` property and an init parameter `solid: SolidRecipe? = nil` (last).

- [ ] **Step 4: Add `createSolid` and share the material code**

In `SceneManager.swift`, add `import CADKernel` at the top. Move the `#if os(macOS)` material block out of `createPrimitive` into:

```swift
    private func makeMaterial(_ color: ColorData) -> SimpleMaterial {
        var material = SimpleMaterial()
        #if os(macOS)
            material.color = .init(
                tint: NSColor(
                    red: CGFloat(color.r),
                    green: CGFloat(color.g),
                    blue: CGFloat(color.b),
                    alpha: CGFloat(color.a)
                ))
        #else
            material.color = .init(
                tint: UIColor(
                    red: CGFloat(color.r),
                    green: CGFloat(color.g),
                    blue: CGFloat(color.b),
                    alpha: CGFloat(color.a)
                ))
        #endif
        return material
    }
```

and use `let material = makeMaterial(color)` in `createPrimitive`. Then add below `createPrimitive`:

```swift
    func createSolid(
        recipe: SolidRecipe,
        name: String? = nil,
        position: SIMD3<Float> = .zero,
        color: ColorData = ColorData(r: 0.8, g: 0.8, b: 0.8)
    ) throws -> CADEntity {
        let mesh = try Self.buildMesh(for: recipe)

        saveUndoState()

        let entityName = name ?? generateName(for: .solid)
        let modelEntity = ModelEntity(mesh: mesh, materials: [makeMaterial(color)])
        modelEntity.position = position
        modelEntity.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        modelEntity.name = entityName
        rootEntity.addChild(modelEntity)

        let cadEntity = CADEntity(
            id: UUID(),
            name: entityName,
            type: .solid,
            entity: modelEntity,
            material: MaterialData(color: color),
            solid: recipe
        )
        entities[cadEntity.id] = cadEntity
        sceneDidChange()
        return cadEntity
    }

    private static func buildMesh(for recipe: SolidRecipe) throws -> MeshResource {
        var solid = try Kernel.extrudeRectangle(width: recipe.width, height: recipe.height, depth: recipe.depth)
        if let radius = recipe.filletRadius {
            solid = try Kernel.fillet(solid, edges: .parallel(to: SIMD3(0, 0, 1)), radius: radius)
        }
        return try MeshResource.generate(from: [Kernel.tessellate(solid).meshDescriptor])
    }
```

The mesh is built before `saveUndoState()` so a kernel failure leaves the scene and the undo stack untouched. The `-π/2` rotation about X turns the kernel's +Z (extrusion direction) into RealityKit's +Y (up).

- [ ] **Step 5: Rebuild blocks from their recipe everywhere entities are recreated**

Add one helper to `SceneManager` and route the three recreation sites through it:

```swift
    private func recreate(
        type: EntityData.EntityType,
        solid: SolidRecipe?,
        name: String,
        position: SIMD3<Float>,
        color: ColorData
    ) -> CADEntity? {
        if type == .solid, let solid {
            return try? createSolid(recipe: solid, name: name, position: position, color: color)
        }
        return createPrimitive(type: type, name: name, position: position, color: color)
    }
```

- `duplicateEntity`: return `recreate(type: original.type, solid: original.solid, name: name, position: original.entity.position + SIMD3<Float>(0.5, 0, 0.5), color: original.material.color)`.
- `restoreSnapshot`: replace the `createPrimitive(...)` call with `recreate(type: data.type, solid: data.solid, name: data.name, position: data.entity.position, color: data.material.color)`, and assign `entities[id] = cadEntity` only when it's non-nil (`if let cadEntity = recreate(...) { entities[id] = cadEntity }`).
- `loadSceneData`: replace `_ = createPrimitive(...)` with `_ = recreate(type: entityData.type, solid: entityData.solid, name: entityData.name, position: entityData.transform.position, color: entityData.material.color)`.
- `toSceneData`: pass `solid: entity.solid` to the `EntityData(...)` initializer.

`try?` in `recreate` drops a block whose recipe no longer builds. That is acceptable for the spike; record it in the findings doc as a follow-up (the feature-tree design needs a visible "failed to rebuild" state).

- [ ] **Step 6: Run the full app test suite**

Run: `xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`. If `undoRestoresSolid` finds two `Bracket` entities, that's the pre-existing `restoreSnapshot` behaviour of re-adding under a new id as well as the old one; the test uses `first { … }` so it still passes, and it isn't in scope here.

- [ ] **Step 7: Commit**

Two commits, since the material refactor stands on its own:

```bash
git add -p 3DModellerApp/Scene/SceneManager.swift   # stage only the makeMaterial extraction
git commit -m "refactor(scene): extract material creation"
git add 3DModellerApp/Scene/SceneDocument.swift 3DModellerApp/Scene/SceneManager.swift 3DModellerAppTests/SolidEntityTests.swift
git commit -m "feat(scene): add kernel-built block entities"
```

---

### Task 6: `create_solid` assistant tool

**Files:**

- Create: `3DModellerApp/Tools/CreateSolidTool.swift`
- Modify: `3DModellerApp/Views/ContentView.swift:93-103` (tool list in `setupAssistant`)
- Test: `3DModellerAppTests/CreateSolidToolTests.swift`

**Interfaces:**

- Consumes: `SceneManager.createSolid`, `SolidRecipe` (Task 5), `KernelError` (Task 1), `AssistantTool`, `ToolParameter`, `ToolExecutionResult`, `JSONValue` (SwiftUIAssistant).
- Produces: `struct CreateSolidTool: AssistantTool` with `id`/`name` `"create_solid"`.

- [ ] **Step 1: Write the failing tests**

`3DModellerAppTests/CreateSolidToolTests.swift`:

```swift
import SwiftUIAssistant
import Testing
@testable import _D_Modeller

@Suite("CreateSolidTool")
@MainActor
struct CreateSolidToolTests {
    @Test("Creates a rounded block from the assistant's arguments")
    func createsBlock() async throws {
        let scene = SceneManager()
        let tool = CreateSolidTool(sceneManager: scene)

        let result = try await tool.execute(arguments: [
            "name": .string("Bracket"),
            "width": .number(0.4),
            "height": .number(0.2),
            "depth": .number(0.1),
            "fillet_radius": .number(0.02),
            "color": .string("blue")
        ])

        #expect(result.success)
        let entity = try #require(scene.entity(named: "Bracket"))
        #expect(entity.solid == SolidRecipe(width: 0.4, height: 0.2, depth: 0.1, filletRadius: 0.02))
        #expect(scene.selectedEntityId == entity.id)
    }

    @Test("Missing dimensions fail without touching the scene")
    func missingDimensions() async throws {
        let scene = SceneManager()
        let tool = CreateSolidTool(sceneManager: scene)

        let result = try await tool.execute(arguments: ["width": .number(0.4)])

        #expect(!result.success)
        #expect(result.message.contains("height"))
        #expect(scene.entities.isEmpty)
    }

    @Test("A fillet that doesn't fit is reported back to the assistant")
    func impossibleFillet() async throws {
        let scene = SceneManager()
        let tool = CreateSolidTool(sceneManager: scene)

        let result = try await tool.execute(arguments: [
            "width": .number(0.1), "height": .number(0.1), "depth": .number(0.1),
            "fillet_radius": .number(0.08)
        ])

        #expect(!result.success)
        #expect(result.message.contains("fillet"))
        #expect(scene.entities.isEmpty)
    }

    @Test("Non-positive dimensions are reported back to the assistant")
    func negativeWidth() async throws {
        let scene = SceneManager()
        let tool = CreateSolidTool(sceneManager: scene)

        let result = try await tool.execute(arguments: [
            "width": .number(-1), "height": .number(0.1), "depth": .number(0.1)
        ])

        #expect(!result.success)
        #expect(result.message.contains("greater than 0"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test -only-testing:3DModellerAppTests/CreateSolidToolTests 2>&1 | tail -20`
Expected: compile failure, `cannot find 'CreateSolidTool' in scope`.

- [ ] **Step 3: Implement**

`3DModellerApp/Tools/CreateSolidTool.swift`:

```swift
import Foundation
import SwiftUIAssistant

struct CreateSolidTool: AssistantTool, @unchecked Sendable {
    let id = "create_solid"
    let name = "create_solid"
    let description = """
        Creates a solid block with exact CAD geometry: a width × height rectangle extruded upward by depth. \
        Optionally rounds the four vertical edges with fillet_radius, which must be less than half of \
        the smaller of width and height.
        """

    let sceneManager: SceneManager

    var parameters: [ToolParameter] {
        [
            ToolParameter(name: "width", type: .number, description: "Size along X in meters", required: true),
            ToolParameter(name: "height", type: .number, description: "Size along Z (depth into the scene) in meters", required: true),
            ToolParameter(name: "depth", type: .number, description: "Extrusion distance upward along Y in meters", required: true),
            ToolParameter(name: "fillet_radius", type: .number, description: "Radius for rounding the vertical edges, in meters", required: false),
            ToolParameter(name: "name", type: .string, description: "Optional name for the entity", required: false),
            ToolParameter(name: "position", type: .object, description: "Position as {x, y, z} in meters", required: false),
            ToolParameter(name: "color", type: .string, description: "Color name (red, blue, green, etc.)", required: false)
        ]
    }

    func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        let dimensions = ["width", "height", "depth"]
        let missing = dimensions.filter { arguments[$0]?.doubleValue == nil }
        guard missing.isEmpty,
              let width = arguments["width"]?.doubleValue,
              let height = arguments["height"]?.doubleValue,
              let depth = arguments["depth"]?.doubleValue
        else {
            return ToolExecutionResult(
                success: false,
                message: "Missing or non-numeric: \(missing.joined(separator: ", "))",
                data: nil
            )
        }

        let recipe = SolidRecipe(
            width: width,
            height: height,
            depth: depth,
            filletRadius: arguments["fillet_radius"]?.doubleValue
        )
        let name = arguments["name"]?.stringValue
        let position = parsePosition(from: arguments["position"]?.objectValue)
        let color = arguments["color"]?.stringValue.map { ColorData(named: $0) } ?? ColorData(r: 0.8, g: 0.8, b: 0.8)

        return await MainActor.run {
            do {
                let entity = try sceneManager.createSolid(recipe: recipe, name: name, position: position, color: color)
                sceneManager.select(id: entity.id)
                return ToolExecutionResult(
                    success: true,
                    message: "Created solid '\(entity.name)'",
                    data: [
                        "entityId": .string(entity.id.uuidString),
                        "entityName": .string(entity.name)
                    ]
                )
            } catch {
                return ToolExecutionResult(success: false, message: "\(error)", data: nil)
            }
        }
    }

    private func parsePosition(from dict: [String: JSONValue]?) -> SIMD3<Float> {
        guard let dict else { return .zero }
        return [dict["x"]?.floatValue ?? 0, dict["y"]?.floatValue ?? 0, dict["z"]?.floatValue ?? 0]
    }
}
```

Register the tool in `ContentView.setupAssistant()` right after `CreatePrimitiveTool(sceneManager: sceneManager),`:

```swift
            CreateSolidTool(sceneManager: sceneManager),
```

- [ ] **Step 4: Run the full app test suite**

Run: `xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add 3DModellerApp/Tools/CreateSolidTool.swift 3DModellerApp/Views/ContentView.swift 3DModellerAppTests/CreateSolidToolTests.swift
git commit -m "feat(assistant): add create_solid tool"
```

---

### Task 7: Measure, verify in the running app, record findings

**Files:**

- Modify: `docs/spikes/2026-09-26-occt-kernel.md`
- Create: `NOTICE`
- Modify: `README.md` (Features list, new "Acknowledgements" section)
- Modify: `CLAUDE.md` (Architecture: package list)

**Interfaces:**

- Consumes: everything above.
- Produces: the findings doc that decides whether OCCTSwift stays.

- [ ] **Step 1: Measure Release size and build times with the kernel**

```bash
SPIKE="${TMPDIR}occt-spike"
xcodegen generate
/usr/bin/time -p xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp -configuration Release \
  -derivedDataPath "$SPIKE/dd-kernel" build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4
APP="$SPIKE/dd-kernel/Build/Products/Release/3D Modeller.app"
du -sk "$APP"; stat -f%z "$APP/Contents/MacOS/3D Modeller"
touch 3DModellerApp/Tools/CreateSolidTool.swift
/usr/bin/time -p xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp -configuration Release \
  -derivedDataPath "$SPIKE/dd-kernel" build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4
```

Fill the "With CADKernel" column and the incremental-build row in the findings doc. Also record the incremental build time for the baseline by repeating the `touch` + build against `dd-baseline` on a checkout of `origin/main` (`git worktree add "$SPIKE/main" origin/main`), then remove that worktree.

- [ ] **Step 2: Verify in the running app**

Use the project's `verify` skill (`.claude/skills/verify/SKILL.md`). Write this scene file and open it, so no API key is needed:

```bash
cat > "$SPIKE/block.scene3d" <<'EOF'
{"entities":[{"id":"0B7E2C1A-2222-4C4D-8E9F-1A2B3C4D5E6F","name":"Bracket","type":"solid",
"transform":{"position":[0,0,0],"rotation":[0,0,0],"scale":[1,1,1]},
"material":{"color":{"r":0.2,"g":0.4,"b":0.9,"a":1},"metallic":0,"roughness":0.5},
"isVisible":true,"solid":{"width":0.4,"height":0.2,"depth":0.1,"filletRadius":0.03}}],
"metadata":{"name":"Spike","createdAt":0,"modifiedAt":0}}
EOF
```

(If `legacyFile` in Task 5 needed a different JSON shape for vectors or dates, use that shape here too.)

Check and screenshot:

- the block sits on the grid, its long side along X, its 0.1 m thickness pointing up, and the rounded corners are visible from above;
- faces are lit from outside, with no black or see-through faces (that would mean a winding or normal problem);
- Duplicate from the outline context menu produces a second rounded block;
- ⌘S, close, reopen: the block is still rounded.

Close the app afterwards: `pkill -f "dd/Build/Products/Debug/3D Modeller.app"`.

- [ ] **Step 3: Write up the findings**

Complete `docs/spikes/2026-09-26-occt-kernel.md` with these sections, using what you measured and saw:

```markdown
## Did it work?

<one paragraph: extrude, fillet, tessellate, render, save/reopen, undo, duplicate: which worked first time, which needed a fix>

## Surprises

<bullets: bounding-box tolerance, winding, orientation, OCCT fillet failure behaviour, build issues; "none" if none>

## Follow-ups

- A block whose recipe no longer builds is silently dropped on load/undo (`SceneManager.recreate` uses `try?`). The feature-tree design needs a visible "failed to rebuild" state.
- Kernel work runs on the main actor inside `createSolid`. Move it off-main before operations get expensive.
- <anything else found>

## Verdict

<keep OCCTSwift pinned / replace with our own bridge / other, in two or three sentences, based on the size and build-time numbers above>
```

- [ ] **Step 4: Credit Open CASCADE**

Create `NOTICE`:

```text
3D Modeller
Copyright 2026 Cedric Ziel

This product uses Open CASCADE Technology (https://dev.opencascade.org),
licensed under the GNU Lesser General Public License version 2.1 with the
Open CASCADE Exception version 1.0, through OCCTSwift
(https://github.com/SecondMouseAU/OCCTSwift), licensed under the GNU Lesser
General Public License version 2.1.
```

In `README.md`, add to the Features list:

```markdown
- **Exact CAD geometry** - Blocks with filleted edges built by the Open CASCADE kernel (early spike)
```

and add a section before the license section (or at the end, if there is none):

```markdown
## Acknowledgements

This app uses [Open CASCADE Technology](https://dev.opencascade.org) (LGPL 2.1 with the Open CASCADE Exception) through [OCCTSwift](https://github.com/SecondMouseAU/OCCTSwift) (LGPL 2.1). See `NOTICE`.
```

In `CLAUDE.md`'s Architecture section, add a `CADKernel` entry next to the existing package descriptions: "`CADKernel` (`Packages/CADKernel/`): the only code that imports OCCTSwift/OpenCASCADE. Exposes `Kernel.extrudeRectangle`, `Kernel.fillet`, `Kernel.tessellate`, `Kernel.metrics`. Test with `cd Packages/CADKernel && xcrun swift test`."

- [ ] **Step 5: Commit**

```bash
git add NOTICE README.md
git commit -m "docs: credit Open CASCADE"
git add CLAUDE.md
git commit -m "docs(claude): describe the CADKernel package"
git add docs/spikes/2026-09-26-occt-kernel.md
git commit -m "docs(spike): record OCCT kernel spike findings"
```
