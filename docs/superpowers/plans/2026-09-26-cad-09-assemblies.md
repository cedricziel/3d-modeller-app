# CAD 09: Assemblies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Documents hold several parts and one assembly of placed instances. Agents add, rename and delete parts, place instances with explicit placements, and measure, list, render and grade across instances. The app shows the assembly. No joints or solver yet (PR 10).

**Architecture:** `CADModel` gains `Assembly { instances }` and `Instance { id, name, part (id), body?, placement, grounded }`. After the parts rebuild, an assembly step moves each instance's part bodies with `GeometryKernel.transform` and reuses the part's mesh and topology, moved rigidly in Swift. Only the metrics come from the kernel, because rotated bounds need it. `ModelGeometry` keys bodies by owner (part id or instance id) and body name. `InstanceResult` resolves face and edge references with the part's names in assembly coordinates, and derives a frame (origin and axes) from a face plus an optional edge, which is the hook for PR 10's joints. `CADAssistantTools` adds part and instance tools, an assembly section in the listing and write reports, instance operands for `measure` and `find_geometry`, and assembly rendering. `cadbench` gains instance checks and assembly tasks. The app lists instances and shows the assembly.

**Tech Stack:** Swift 6, Swift Testing, `simd` (`simd_quatd`, `simd_double3x3`), OCCT through `CADKernel` (`Kernel.transform` keeps face names), SwiftUI and RealityKit.

**Spec:** `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md` (sections "Document": assembly; "Agent tools": `add_part`, `add_instance`; "Assemblies and motion": interference between instances; PR-stack row 9). Previous layers: `docs/superpowers/plans/2026-09-26-cad-02-document-model.md`, `-03-assistant-tools.md`, `-05-naming.md`, `-06-feedback.md`, `-08-sketches.md`.

## Global Constraints

- macOS 26, Apple Silicon only (`ARCHS: arm64`), Swift 6 strict concurrency. Use `xcrun swift`, never bare `swift`.
- Only `CADKernel` imports OCCTSwift. Every OCCT call runs inside `OCCTSerial.withLock {}`. No C++ exception may reach Swift; failures are typed errors.
- `CADModel` stays pure Swift and reaches geometry only through `GeometryKernel`.
- The model, tools and listing use millimetres and degrees.
- The agent-facing surface (document, rebuild, tools) runs without the app or any UI.
- Tests use Swift Testing and never block a cooperative thread. They must finish under `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`.
- Commits are semantic, one concern each, with no "and" in the subject and no co-author lines. Comments only state a non-obvious why.
- Hoist long expressions inside `#expect` into typed `let`s, and annotate closure types, because CI type-checks slowly.
- Keep clean builds and derived data in the scratchpad, and delete them afterwards.

## Rulings

- **Ruling: `Assembly` has no `joints` field in this layer.** PR 10 adds `joints: [Joint]`, decoded with `decodeIfPresent`, so documents saved by this layer load there. The format stays 1. Cost if wrong: none; one optional key.
- **Ruling: `CADDocument.assembly` stays optional.** `nil` means no assembly, and the listing and outline omit the section. An assembly with no instances is shown as "(no instances)". `add_instance` creates the assembly when needed. `delete_instance` keeps an empty assembly. Cost if wrong: none.
- **Ruling: an `Instance` refers to its part by id.** A missing part fails the instance with "its part no longer exists" (possible only in hand-edited files, because `delete_part` refuses parts that instances use). Instance ids join the decoder's duplicate-id check. Cost if wrong: none.
- **Ruling: `body: nil` places every body the part builds.** A named body that the part did not build fails the instance, and the error lists the bodies that exist. The instance's bodies keep the part's body names. Cost if wrong: none.
- **Ruling: instance placements use the document `Placement`,** with scalars that may be parameter expressions: rotate by `rotationDegrees` about `rotationAxis` through the origin, then translate. This matches features and `Kernel.transform`. Cost if wrong: none; a real-kernel test pins the convention.
- **Ruling: per instance body, `kernel.transform` moves the part's built kernel body and `kernel.metrics` measures it.** Rotated axis-aligned bounds need the kernel. The mesh and topology are the part's, moved in Swift by `RigidTransform`, so nothing is tessellated or described twice. Face and edge indices stay aligned, because a moved shape keeps its sub-shape order. A real-kernel test compares the moved topology with `kernel.topology` of the moved body. Cost if wrong: one kernel topology call per instance body.
- **Ruling: instance statuses are `InstanceStatus.ok` or `.failed(String)`.** Failures are: a duplicate name, a missing part, a placement expression that does not evaluate, a missing body, a part with no bodies, or a kernel error. A failed instance has no bodies. Cost if wrong: none.
- **Ruling: measured bodies are keyed by `BodyKey(owner: .part(id) | .instance(id), body:)`.** This fixes the limitation of keying by part name. Tools make the labels. Cost if wrong: none.
- **Ruling: an instance reference is `{instance, body?, face | edge}`.** Without `body`, a face or edge name must match in exactly one of the instance's bodies. Measuring or interfering a whole instance with several bodies needs `body`. Cost if wrong: one more argument for multi-body instances.
- **Ruling: frames.** z is the planar face's outward normal, or the axis of a cylinder, cone or torus. A sphere or an "other" face is refused. The origin is the edge's centre (circle) or midpoint (line) when an edge is given. Otherwise it is the planar face's centroid, or the face centroid projected onto the axis. x is a straight edge's direction projected onto the plane perpendicular to z; otherwise it is the first of global X, Y, Z whose projection is longer than 0.1, normalised. y = z × x. The edge refines the frame; it need not bound the face. Cost if wrong: PR 10 may need a stricter rule; the helper is small.
- **Ruling: part and instance names are identifiers** (letters, digits and `_`) and are unique per document. The tools enforce this; the decoder accepts older names. `delete_part` refuses the last part and any part that instances use. Default names are `Part<n>` and `<Part><n>`. Cost if wrong: none.
- **Ruling: `edit_instance` changes placement fields (merged like `edit_feature`), `grounded` and `new_name`.** Changing the part or body means deleting and adding the instance. Cost if wrong: an extra call.
- **Ruling: instance body references are repaired like feature body references.** When `Body2` becomes `Body1`, an instance's `body` follows. An edit that removes the body refuses. Instance placement expressions join the expression audit. Cost if wrong: none.
- **Ruling: `render_views` takes `show: parts | assembly`.** The default is `assembly` when an instance has a mesh, otherwise `parts`. Each instance gets its own colour. Cost if wrong: none.
- **Ruling: the app's viewport shows the assembly when the document has instances, and parts otherwise.** A segmented control (Parts | Assembly) appears only when there are instances. Selecting a feature switches to parts; selecting an instance switches to assembly. The inspector shows instances read-only. Cost if wrong: a UI preference.
- **Ruling: bench checks.** `instanceCount { equals }`, `instanceBounds { instance?, min/max/size, tolerance }` (without `instance`, every instance), `noInterference {}` (every pair of instance bodies shares no volume; touching is allowed). The gate fails on a failed instance. `referenceIoU` compares instance solids when the reference has instances. `unchangedExcept` gains `instances: [names]` and compares instances by name (part name, body, placement, grounded). Cost if wrong: none.

- **Ruling (execution): a part name shared by several parts** (possible only in hand-edited files; the tools refuse duplicates) picks the first part in document order instead of being refused. Geometry is keyed by id, so no mix-up is possible. Cost if wrong: the agent measures the first of two same-named parts.
- **Ruling (execution): the tools' fake kernel moves bodies by translation only.** Rotation is covered by the real-kernel tests. Cost if wrong: none.
- **Ruling (execution): the chosen viewport content persists for the window.** It is ignored, not reset, while the document has no instances. Cost if wrong: a UI preference.
- **Ruling (execution): commits are grouped by file:**
  - Task 4 references and frames: one commit.
  - Task 6 instance tools, report and repair: one commit.
  - Task 7 measure, find and render: one commit, "inspect instances where they are placed".
  - Task 9 app: one commit.

  Cost if wrong: coarser history.
- **Ruling (review): an instance resolves face and edge names with its part's own `TopologyNames`, computed before the move** (`InstanceResult.names(of:)`). `[n]` pieces are ordered by position, so a rotation would otherwise renumber them. Cost if wrong: none.

## Deferred after the final review

- The rotated-instance kernel test compares faces only, not edge fields or face `axis`/`axisOrigin`.
- The chosen viewport content never resets when the instances go to zero and come back.
- `noInterference` skips body pairs without metrics instead of reporting them. The gate ignores instance body errors, such as metrics failing on a moved body.
- `stacked-plates` and `table-legs` do not grade "model once, place several times", or `Bottom` being grounded.
- The `InstanceResult.transform` doc says it is nil only for placement errors; it is nil for every failure.
- Write reports list every unchanged instance name, with no cap.
- `add_instance`'s default name, built from a part name that is not an identifier, is refused.
- With duplicate instance names in a hand-edited file, `edit_instance` and `delete_instance` reach only the first.
- `render_views` does not note an ok instance body that has no mesh.
- Four pre-existing `CADSessionTests` still time out under `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`: their `Gate` blocks a cooperative thread by design.

## Review Focus

1. **An instance whose part body disappears** (a feature deletes or breaks the body, or a named body does not exist). Expected: the instance fails with a message listing the bodies that exist. Other instances and the parts still build. Pinned in Task 3 (`missingBodyFails`, `brokenPartBodyFailsInstance`).
2. **A rotated instance.** Expected: bounds, face centroids and normals in assembly coordinates match the kernel's own topology of the moved body. Measuring a face of a rotated instance uses the right face. Pinned in Task 3 (`rotatedInstanceMatchesKernel`, real kernel).
3. **Deleting a part that instances use, or renumbering a body an instance names.** Expected: `delete_part` refuses and names the instances. Deleting `Body1`'s creator renames the instance body reference to the new name and reports it, or refuses when the body would vanish. Pinned in Task 6 (`deletePartRefused`, `instanceBodyRepaired`).
4. **Two instances of one part, in contact and overlapping.** Expected: `measure interference` reports "touch without overlapping" for stacked plates and the shared volume for overlapping ones. `noInterference` passes and fails accordingly. Pinned in Task 7 (`interferenceBetweenInstances`, real kernel) and Task 8 (wrong solution `topPlateSunk`).
5. **Duplicate instance names in a hand-edited file, and an instance placement expression over a missing parameter.** Expected: the second instance fails "another instance is already named …" and the expression fails naming the field. Tools refuse to create either. Pinned in Task 3 (`duplicateAndExpressionFailures`) and Task 6 (`addInstanceRefusals`).

## File Structure

`Packages/CADModel/Sources/CADModel/`:

- `Assembly.swift` (new): `Assembly`, `Instance`, `CADDocument` instance helpers.
- `CADDocument.swift`: remove the old empty `Assembly`, extend the duplicate-id check.
- `RigidTransform.swift` (new): `RigidTransform` and moving `BodyTopology`, `BodyMesh` and `Bounds`.
- `AssemblyResult.swift` (new): `InstanceStatus`, `InstanceResult`, `AssemblyResult`.
- `AssemblyBuilder.swift` (new): places the instances.
- `InstanceGeometry.swift` (new): references and frames on instances.
- `RebuildResult.swift`, `RebuildEngine.swift`, `RebuildEngine+Solids.swift`, `ModelGeometry.swift`: modified.

`Packages/CADModel/Tests/`:

- `CADModelTests/`: `AssemblyCodingTests.swift`, `RigidTransformTests.swift`, `AssemblyRebuildTests.swift`, `InstanceGeometryTests.swift` (all new), `ModelGeometryTests.swift`.
- `CADModelKernelTests/AssemblyKernelTests.swift` (new).

`Packages/CADAssistantTools/Sources/CADAssistantTools/`:

- `PartTools.swift` (new): `AddPartTool`, `RenamePartTool`, `DeletePartTool`.
- `InstanceTools.swift` (new): `AddInstanceTool`, `EditInstanceTool`, `DeleteInstanceTool`.
- `PlacementArguments.swift` (new).
- `AssemblyListing.swift` (new).
- Modified: `DocumentListing.swift`, `WriteReport.swift`, `BodyReferenceRepair.swift`, `ExpressionAudit.swift`, `Arguments.swift`, `MeasureOperand.swift`, `MeasureTool.swift`, `FindGeometryTool.swift`, `RenderViewsTool.swift`, `CADTools.swift`, `CADAssistantPrompt.swift`.
- Tests: `PartToolTests.swift`, `InstanceToolTests.swift`, `AssemblyMeasureTests.swift` (new), `RenderViewsToolTests.swift`, `DocumentListingTests.swift`, `FakeKernel.swift` (rotation-aware transform).

`CADBench`: `Check.swift`, `Grader.swift`, `DocumentComparison.swift`, `BenchTask.swift` (loader checks). Tests: `TaskGradingTests.swift`, `CheckDecodingTests.swift`, `GraderTests.swift`. Tasks: `Bench/tasks/{stacked-plates,table-legs,move-instance}/`, `Bench/README.md`.

App: `Views/FeatureOutlineView.swift`, `Views/ContentView.swift`, `Views/InstanceInspectorView.swift` (new), `Viewport/ViewportContent.swift` (new), `Viewport/ViewportScene.swift`, `Viewport/ViewportFrame.swift`, `Views/Viewport3DView.swift`. Tests: `3DModellerAppTests/AssemblyDisplayTests.swift` (new). Docs: `CLAUDE.md`.

---

### Task 1: Assembly model and coding

**Files:** create `Assembly.swift` and `Tests/CADModelTests/AssemblyCodingTests.swift`; modify `CADDocument.swift`.

**Produces:**

```swift
public struct Instance: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// The id of the part it places.
    public var part: UUID
    /// One body of the part, or every body when nil.
    public var body: String?
    public var placement: Placement
    public var grounded: Bool
    public init(id: UUID = UUID(), name: String, part: UUID, body: String? = nil,
                placement: Placement = .identity, grounded: Bool = false)
    // decode: id default UUID(), body/placement/grounded optional
}

public struct Assembly: Codable, Sendable, Hashable {
    public var instances: [Instance]
    public init(instances: [Instance] = [])   // decode: instances default []
}

extension CADDocument {
    public var instances: [Instance] { assembly?.instances ?? [] }
    public func part(id: UUID) -> Part?
    public func instance(named name: String) -> Instance?
}
```

JSON: `"assembly": {"instances": [{"id": …, "name": "Lid", "part": "<part uuid>", "body": "Body1", "placement": {…}, "grounded": true}]}`. The encoder writes `body` only when it is set.

- [ ] **Step 1: failing tests.** `roundTrip`: a document with two parts and three instances (one with a body, one grounded, one rotated with an expression) encodes and decodes equal, and the JSON contains `"grounded" : true`. `defaults`: `{"name": "A", "part": "<id>"}` decodes with identity placement, `grounded` false, body nil. `earlierDocumentsLoad`: format-1 JSON with no `assembly` key, and one with `"assembly": {}`, decode to `nil` and to an empty assembly. `duplicateInstanceID`: an instance sharing a part's id throws `DocumentError.duplicateID`.
- [ ] **Step 2:** `cd Packages/CADModel && xcrun swift test --filter AssemblyCoding`. Expect a compile failure.
- [ ] **Step 3:** implement. Add the instance ids to the id set in `CADDocument.init(from:)`, and change the `duplicateID` text to "More than one part, feature or instance has the id".
- [ ] **Step 4:** run the whole CADModel suite.
- [ ] **Step 5:** commit `feat(model): store assembly instances`.

### Task 2: Rigid transforms and body keys by owner

**Files:** create `RigidTransform.swift` and `RigidTransformTests.swift`; modify `ModelGeometry.swift` (`BodyKey`), `RebuildEngine.swift` and `ModelGeometryTests.swift`. In `CADAssistantTools`, modify `MeasureOperand.swift` and `MeasureTool.swift` to build the key from the part id and make their own labels.

**Produces:**

```swift
public struct RigidTransform: Sendable, Equatable {
    public var rotation: simd_double3x3
    public var translation: SIMD3<Double>
    public static let identity: RigidTransform
    /// Rotation by `rotationDegrees` about the normalised axis through the origin, then the translation.
    public init(_ placement: ResolvedPlacement)
    public func point(_ p: SIMD3<Double>) -> SIMD3<Double>
    public func direction(_ d: SIMD3<Double>) -> SIMD3<Double>
}
extension BodyTopology { public func transformed(by t: RigidTransform) -> BodyTopology }
extension BodyMesh { public func transformed(by t: RigidTransform) -> BodyMesh }

public struct BodyKey: Sendable, Hashable {
    public enum Owner: Sendable, Hashable { case part(UUID), instance(UUID) }
    public var owner: Owner
    public var body: String
    public init(owner: Owner, body: String)
    public init(part: UUID, body: String)          // .part owner
}
```

`RigidTransform.init` uses `simd_quatd(angle: degrees·π/180, axis: simd_normalize(axis))`. A zero axis or a zero angle gives the identity rotation. Faces move the centroid, `axisOrigin`, `normal` and `axis`; edges move `start`, `end`, `midpoint`, `center`, `direction` and `axis`. Meshes move their positions and normals as `Float`. `Measurer`'s error for an unknown key becomes "\(key.body) was not built". `RebuildEngine.build` keys part bodies with `BodyKey(part: part.id, body:)`. `MeasureOperand` drops the "several parts are named" refusal.

- [ ] **Step 1: failing tests.** A 90° rotation about Z maps (1, 0, 0) to (0, 1, 0) within 1e-12, with the translation applied after the rotation. Box topology moved by 90° about X plus (0, 0, 5): the `top` face normal becomes (0, −1, 0) and its centroid moves accordingly, and names are kept. A mesh moves and its normals rotate. `ModelGeometryTests` uses `BodyKey(part: document.parts[0].id, body:)`. A new test: two parts with the same name are measured separately.
- [ ] **Step 2:** run and see it fail. **Step 3:** implement. **Step 4:** run the CADModel and CADAssistantTools suites (`MeasureToolTests` labels stay "Body1 (Plate)").
- [ ] **Step 5:** commit `feat(model): move topology and meshes rigidly`, then `fix(model): key measured bodies by part id`.

### Task 3: Placing instances on rebuild

**Files:** create `AssemblyResult.swift`, `AssemblyBuilder.swift`, `AssemblyRebuildTests.swift` and `CADModelKernelTests/AssemblyKernelTests.swift`; modify `RebuildResult.swift`, `RebuildEngine.swift` and `RebuildEngine+Solids.swift`.

**Produces:**

```swift
public enum InstanceStatus: Sendable, Equatable, CustomStringConvertible { case ok, failed(String) }  // "ok", "failed: …"
public struct InstanceResult: Sendable, Equatable, Identifiable {
    public let id: UUID; public let name: String; public let part: UUID
    public let status: InstanceStatus
    public let transform: RigidTransform?          // nil when the placement did not resolve
    public let bodies: [BodyResult]                // in assembly coordinates, part body names
}
public struct AssemblyResult: Sendable, Equatable {
    public let instances: [InstanceResult]
    public func instance(id: UUID) -> InstanceResult?
    public func instance(named: String) -> InstanceResult?
}
// RebuildResult gains: public let assembly: AssemblyResult?; public var failedInstanceCount: Int
extension RebuildEngine {
    /// Each ok instance's moved kernel bodies, for callers that combine bodies further.
    @concurrent public func instanceSolids(of document: CADDocument) async throws -> [BuiltBody<Kernel.Body>]
}
```

`AssemblyBuilder<Kernel>` takes `(kernel, parameters)`, the part bodies built so far (`[UUID: [(name: String, body: Kernel.Body)]]`) and the part results.

- `place(_ instance:, seenNames:) throws(InstanceFailure) -> (RigidTransform, [(name: String, body: Kernel.Body)])` checks the name, looks up the part, resolves the placement (`FeatureError.expression`-style text "placement.translation.x: …"), selects the bodies and transforms them.
- `results(...)` builds each `BodyResult`: kernel metrics of the moved body (an error goes to `BodyResult.error`), and the part's mesh and topology moved by `RigidTransform`.

`build` adds `BodyKey(owner: .instance(id), body:)` entries to the geometry.

- [ ] **Step 1: failing tests (fake kernel).**
  - `placesInstances`: part `Plate` (a box) placed twice with translations. The results have two ok instances. Their topology centroids are shifted. Their meshes are shifted. The part is built once: the fake kernel's `box` call count is 1.
  - `missingBodyFails`: `body: "Body3"` fails with "part Plate has no body named Body3; bodies: Body1".
  - `brokenPartBodyFailsInstance`: the part's only feature fails, so the instance fails with "part Plate has no bodies".
  - `missingPartFails`.
  - `duplicateAndExpressionFailures`: the second "A" fails with "another instance is already named A", and `"z": "nope * 2"` fails naming `placement.translation.z`.
  - `noAssemblyNoResult`: a document without an assembly has `result.assembly == nil`.
  - `geometryKeysInstances`: distance between two instance keys.
- [ ] **Step 2: failing tests (real kernel, `AssemblyKernelTests`).**
  - `rotatedInstanceMatchesKernel`: a 60×40×10 box, instance rotated 90° about Z and moved by (100, 0, 0). The bounds are (60, 0, 0)…(100, 60, 10) within 1e-3. For every face, the moved topology's centroid and normal equal `kernel.topology(of: kernel.transform(...))` within 1e-6, in the same order.
  - `instanceSolidsVolume`: two instances give two solids of 24000 mm³.
- [ ] **Step 3:** implement. **Step 4:** run both CADModel suites (`xcrun swift test` in `Packages/CADModel`).
- [ ] **Step 5:** commit `feat(model): place instances on rebuild`.

### Task 4: References and frames on instances

**Files:** create `InstanceGeometry.swift` and `InstanceGeometryTests.swift`; add a real-kernel frame test to `AssemblyKernelTests`.

**Produces:**

```swift
public struct Frame: Sendable, Equatable { public var origin, xAxis, yAxis, zAxis: SIMD3<Double> }
public struct InstanceElement: Sendable, Equatable {
    public let body: String; public let kind: GeometryKind; public let index: Int; public let name: String
}
extension InstanceResult {
    /// A name or filter resolved against the instance's bodies (or `body` alone); must match exactly one.
    public func element(_ reference: GeometryReference, _ kind: GeometryKind, body: String?,
                        parameters: ParameterTable) throws(ReferenceError) -> InstanceElement
    public func frame(face: GeometryReference, edge: GeometryReference?, body: String?,
                      parameters: ParameterTable) throws(ReferenceError) -> Frame
}
public enum GeometryFrame {
    public static func frame(face: FaceDescriptor, edge: EdgeDescriptor?) throws(ReferenceError) -> Frame
}
```

An instance whose status is not ok throws "instance X did not build: …". A name that matches in several bodies throws "'Box.top' matches in Body1 and Body2 of X; add 'body'".

- [ ] **Step 1: failing tests.**
  - An instance moved by (0, 0, 20): `element(.name("Box.top"), .faces)` resolves to the top face.
  - Its frame has origin (w/2, d/2, h + 20), zAxis (0, 0, 1), xAxis (1, 0, 0).
  - With `edge(Box.front, Box.top)`, the origin is that edge's midpoint and xAxis is along the edge.
  - A cylinder side face gives the axis as z and the origin on the axis at the centroid's height.
  - A circular edge gives the circle centre as the origin.
  - A sphere face is refused.
  - A two-body instance needs `body` for a name found in both bodies.
  - Real kernel: a cylinder instance rotated 90° about X has frame z = ±(0, −1, 0), matching the moved axis.
- [ ] **Steps 2–4:** run, implement, run.
- [ ] **Step 5:** commit `feat(model): resolve references on instances`, then `feat(model): derive frames from instance faces`.

### Task 5: Listing and write reports for assemblies

**Files:** create `AssemblyListing.swift`; modify `DocumentListing.swift` (make `location` internal) and `WriteReport.swift` (instance focus, status changes, instance lines). Tests: `DocumentListingTests.swift` and `WriteReportTests.swift`.

The listing appends:

```
assembly
  Base  Plate at origin, grounded  ok
  Lid  Plate/Body1 at (0, 0, 15) rotated 90° about (0, 0, 1)  ok
  Ghost  (missing part)  failed: its part no longer exists
```

`WriteFocus` gains `instance: UUID?`. The report prints `Lid: ok` for the focus, and lists instance status changes under "Status changes elsewhere". An "Instances:" block shows changed or faulty instances in full (`Lid (Plate): ok, bounds (0, 0, 15) to (60, 40, 20)`). Unchanged instances appear as "Unchanged instances: Base", removed ones as "Removed instances: …".

- [ ] Steps: failing tests (the listing with and without an assembly; an empty assembly shows "(no instances)"; a statusless listing says "not built"), implement, run, commit `feat(tools): list the assembly`, then `feat(tools): report instances after writes`.

### Task 6: Part and instance tools

**Files:** create `PartTools.swift`, `InstanceTools.swift`, `PlacementArguments.swift`, `PartToolTests.swift` and `InstanceToolTests.swift`; modify `Arguments.swift` (`Naming.checkPartName`, `checkInstanceName`, `CADDocument.instanceIndex(named:)`), `BodyReferenceRepair.swift` (instances), `ExpressionAudit.swift` (instance placements), `CADTools.swift`, and the tools test `FakeKernel.swift` (rotation-aware bounds in `transform`).

```swift
struct PlacementArguments {
    init(_ object: [String: JSONValue]) throws(ToolError)  // translation (object or [x,y,z]), rotationAxis, rotationDegrees
    func applied(to placement: Placement) -> Placement      // only given components change
}
```

Tools and their arguments:

| Tool              | Arguments                                                      |
| ----------------- | -------------------------------------------------------------- |
| `add_part`        | `name?`                                                        |
| `rename_part`     | `part`, `new_name`                                             |
| `delete_part`     | `part`                                                         |
| `add_instance`    | `part` (required), `name?`, `body?`, `placement?`, `grounded?` |
| `edit_instance`   | `instance`, `placement?`, `grounded?`, `new_name?`             |
| `delete_instance` | `instance`                                                     |

Every tool goes through `write`. Refusals:

- `add_part`: a duplicate or invalid name.
- `delete_part`: the last part; a part that instances use, listing them.
- `add_instance`: an unknown part, a duplicate or invalid name, a body the part does not build right now (checked against the current result when it is current), an expression over an unknown parameter (by the audit).
- `edit_instance`: nothing given.

- [ ] **Step 1: failing tests.**
  - `addRenameDeletePart`: add `Leg`; rename it to `Post`; the listing shows `part Post`; delete it.
  - `deletePartRefused`: the only part; a used part ("used by instances Leg1, Leg2").
  - `addInstanceDefaults`: `add_instance {part: Plate}` makes `Plate1`, and the second one `Plate2`. The report shows "Plate1: ok" and the bounds.
  - `addInstanceRefusals`: an unknown part, `name: "A B"`, a duplicate name, `body: "Body9"`, `placement.translation.z: "missing + 1"`.
  - `editInstanceMerges`: z only keeps x and y; `grounded`; `new_name`.
  - `deleteInstance`.
  - `instanceBodyRepaired`: part features Box A, Box B, instance body `Body2`. Deleting A renames the instance body to `Body1` and reports "Lid now refers to Body1 (was Body2)". Deleting B refuses: "Lid uses Body2, which B creates".
  - Undo: each tool is one commit named "Add part Leg", "Add instance Plate1", and so on.
- [ ] **Steps 2–4:** run, implement, run the tools suite.
- [ ] **Step 5:** commit `feat(tools): add, rename and delete parts`, `feat(tools): place instances through the assistant tools`, then `fix(tools): repair instance body references`.

### Task 7: Measuring, finding and rendering across instances

**Files:** modify `MeasureOperand.swift` (`instance` key), `MeasureTool.swift` (schema, description, interference between instances), `FindGeometryTool.swift` (`instance` argument), `RenderViewsTool.swift` (`show`) and `CADAssistantPrompt.swift` (a "## Parts and assemblies" section). Tests: `AssemblyMeasureTests.swift` (fake and real kernel) and `RenderViewsToolTests.swift`.

The operand keys become `part | instance`, `body`, `face | edge`, or `point`. With `instance`, the face or edge resolves through `InstanceResult.element`. The label is "Head.bottom of Bolt1" or "Bolt1" (with "/Body2" when the instance has several bodies). The target is `BodyKey(owner: .instance(id), body:)`. `find_geometry` accepts `instance` in place of `part`, with `body` optional when the instance has one body. Its header is "Bolt1 (Bolt/Body1)" and coordinates are in the assembly.

- [ ] **Step 1: failing tests.**
  - `measureInstanceFace` (fake): the size of `{instance: "Lid", face: "Box.top"}` has a centre shifted by the placement.
  - `interferenceBetweenInstances` (real kernel): plates at z 0 and z 10 (thickness 10) "touch without overlapping"; at z 5 they "overlap by 12000 mm³"; at z 30 the clearance is 10.
  - `mixedOperand`: a part body against an instance measures the distance.
  - `refusals`: `part` and `instance` together; an unknown instance lists the instances; a multi-body instance without `body`.
  - `findGeometryOnInstance`.
  - `renderAssembly`: the default shows instances ("Base (Plate) blue, Lid (Plate) orange"); `show: parts` shows bodies; `show: assembly` without instances is refused.
- [ ] **Steps 2–4:** run, implement, run.
- [ ] **Step 5:** commit `feat(tools): measure across instances`, `feat(tools): render the assembly`, then `docs(tools): teach the assistant assemblies`.

### Task 8: Bench

**Files:** `Check.swift` (new cases, decoding, descriptions), `Grader.swift` (uses `build`; gate includes instances; the new checks; instance IoU), `DocumentComparison.swift` (instances), `BenchTask.swift` (none), the tasks, `TaskGradingTests.swift`, `CheckDecodingTests.swift` and `Bench/README.md`.

Tasks (all parts at the origin; instances carry the placements):

- `stacked-plates` (build): part `Plate` 60×40×5 (box at the origin), part `Spacer` 20×20×10. Instances: `Bottom` Plate at the origin, grounded; `Spacer` at (20, 10, 5); `Top` Plate at (0, 0, 15). Checks: gate, instanceCount 3, instanceBounds Top min (0, 0, 15) max (60, 40, 20), instanceBounds (all) (0, 0, 0)…(60, 40, 20), noInterference, referenceIoU 0.999. Wrong solutions: `topPlateSunk` (Top at z 10; caught by noInterference), `platesAsBodies` (one part with three bodies, no instances; caught by instance count).
- `table-legs` (build): part `Top` 100×60×4, part `Leg` 5×5×70. `Top` at (0, 0, 70); `Leg1`…`Leg4` at (2, 2, 0), (93, 2, 0), (2, 53, 0), (93, 53, 0). Checks: gate, instanceCount 5, instanceBounds (all) (0, 0, 0)…(100, 60, 74), instanceBounds Leg4 min (93, 53, 0), noInterference, referenceIoU 0.999. Wrong solution: `legTooLong` (Leg made 74 tall; caught by noInterference).
- `move-instance` (modify): the seed is the stacked plates with `Top` at z 15. Prompt: move `Top` up by 10 mm so it sits at z = 25, changing nothing else. Checks: gate, instanceCount 3, instanceBounds Top min (0, 0, 25) max (60, 40, 30), unchangedExcept instances [Top], referenceIoU 0.999. Wrong solutions: `movedByEditingPart` (a transform feature added to Plate moves both plates; caught by "unchanged"), `movedSpacer` (caught by "unchanged").

- [ ] Steps: failing decoding tests for the new checks; grader unit tests (fake kernel) for `instanceCount`, `instanceBounds`, `noInterference` and the gate on a failed instance; `unchangedExcept` with instances. Then implement, write the task files with explicit part ids, add the ids and wrong solutions to `TaskGradingTests`, and update the README tables. Commit `feat(bench): grade assemblies`, then `feat(bench): add assembly tasks`.

### Task 9: App

**Files:** create `Viewport/ViewportContent.swift`, `Views/InstanceInspectorView.swift` and `3DModellerAppTests/AssemblyDisplayTests.swift`; modify `FeatureOutlineView.swift`, `ContentView.swift`, `ViewportScene.swift`, `ViewportFrame.swift` and `Viewport3DView.swift`.

```swift
enum ViewportContent: String, CaseIterable, Identifiable { case parts, assembly
    static func automatic(for document: CADDocument) -> ViewportContent   // assembly when instances exist
    static func following(selection: UUID?, in document: CADDocument) -> ViewportContent?  // feature → parts, instance → assembly
}
struct DisplayBody: Equatable { let name: String; let mesh: BodyMesh; let bounds: (SIMD3<Double>, SIMD3<Double>)? }
extension RebuildResult { func displayBodies(_ content: ViewportContent) -> [DisplayBody] }
```

`ViewportScene.show(_ result:, content:)` draws `displayBodies` and hides sketches for the assembly. `ViewportFrame.sceneBounds(of:content:)` covers the displayed bodies. The outline gets an "Assembly" section with instance rows (`shippingbox` symbol, name, part name, status icon), tagged by instance id. The inspector shows `InstanceInspectorView` for an instance: name, part, body, position, rotation, grounded, status and bounds, all read-only.

- [ ] Steps: failing app tests (`automatic` for documents with and without instances; `following` for a feature id, an instance id and nil; `displayBodies` of a real rebuild of two instances gives two meshes named "Base" and "Lid" with shifted bounds; scene entities are named after the instances). Then implement, run `xcodegen generate` (only if files need regenerating), and run `xcodebuild … test` with derived data in the scratchpad. Commit `feat(app): show the assembly in the viewport`, then `feat(app): list instances in the outline`.

### Task 10: Docs, checks, final review

- [ ] `CLAUDE.md`: assemblies in the architecture section. CI needs no new step. Commit `docs: describe assemblies`.
- [ ] Clean `xcrun swift test --package-path <pkg> --scratch-path <scratchpad>/clean` for CADModel and CADAssistantTools, a long-expression check at 150 ms, and a strict-pool run with `timeout 300`.
- [ ] A fresh `opus` reviewer over `git merge-base cad/08-sketches HEAD..HEAD`, then one fix pass for Critical and Important findings. Record the rulings and deferred items in this plan.

## Self-review

- **Spec coverage.** Multi-part documents and part tools: Tasks 1 and 6. Part-id keys: Task 2. The assembly model: Task 1. The rebuild with instance results: Task 3. Instance references, interference and frames: Tasks 4 and 7. Instance tools, listing and render: Tasks 5–7. The app: Task 9. The bench: Task 8. Joints are deferred to PR 10 by ruling.
- **Types.** `Instance`, `Assembly`, `InstanceResult`, `AssemblyResult`, `InstanceStatus`, `RigidTransform`, `BodyKey.Owner`, `Frame`, `InstanceElement`, `GeometryFrame`, `ViewportContent` and `DisplayBody` keep these names across tasks.
