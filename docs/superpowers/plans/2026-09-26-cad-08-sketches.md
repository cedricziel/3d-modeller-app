# CAD 08: Sketches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agents and users model from sketches: a `sketch` feature (plane, named entities, named constraints) solved by PlaneGCS on every rebuild, `extrude` and `revolve` features that turn its closed loops into solids with faces named `Extrude1.side[Sketch1.line3]`, `Extrude1.start`, `Extrude1.end`, sketch tools for the assistant, sketch display in the app and sketch tasks in `cadbench`.

**Architecture:** `CADKernel` builds planar faces with holes from 2D profile curves on a placed plane and extrudes or revolves them, naming faces geometrically (caps by plane, sides by the profile curve their bottom edge lies on). `CADModel` stores sketches with stable entity and constraint names, compiles them into a solver-agnostic `SketchSystem` for a `SketchSolving` protocol, finds closed loops and nested regions in the solved geometry, and builds extrude and revolve through `GeometryKernel`. A new target `CADModelSolvers` in the `CADModel` package adapts `CADSolvers` to `SketchSolving`. `CADAssistantTools` adds `add_sketch`, `edit_sketch`, `get_sketch`, extrude/revolve in `add_feature`/`edit_feature` and sketch lines in the listing. The app draws solved sketches on their planes.

**Tech Stack:** Swift 6 (tools 6.1 for the OCCT/solver packages), Swift Testing, OCCTSwift 3.0.0 (`Wire.line(from:to:)`, `Wire.arc(start:midpoint:end:)`, `Wire.circle(origin:normal:radius:)`, `Wire.join`, `Shape.face(outer:holes:)`, `Shape.extruded(by:)`, `Shape.revolved(axisOrigin:axisDirection:angle:)`, `Shape.compound`), `CADSolvers` (PlaneGCS), RealityKit.

**Spec:** `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md` (sections "Document" — feature kinds sketch/extrude/revolve, "Naming geometry", "Agent tools", "Sketches", PR-stack row 8). Previous layers: `docs/superpowers/plans/2026-09-26-cad-05-naming.md`, `-06-feedback.md`, `-07-sketch-solver.md`.

## Global Constraints

- macOS 26, Apple Silicon only (`ARCHS: arm64`), Swift 6 strict concurrency. Use `xcrun swift`, never bare `swift`.
- Only `CADKernel` imports OCCTSwift; every OCCT call runs inside `OCCTSerial.withLock {}`. Only `CADSolvers` contains C++ solver code. No C++ exception may reach Swift; failures are typed errors.
- `CADModel` stays pure Swift and solver-agnostic; it reaches geometry through `GeometryKernel` and sketches through `SketchSolving`.
- Millimetres and degrees in the document, tools and listing; radians only inside `CADKernel`/`CADSolvers` calls.
- The agent-facing surface (document, rebuild, tools) runs without the app or any UI.
- Tests use Swift Testing and never block a cooperative thread; they finish under `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`.
- Semantic commits, one concern each, no "and" in the subject, no co-author lines. Comments only for a non-obvious why.
- No two targets in one package differ only by case. Clean builds and derived data go to the scratchpad and are deleted afterwards.
- Long expressions inside `#expect` are hoisted into typed `let`s (CI type-checks slowly).

## Rulings

- **Ruling: the solver adapter is a new target `CADModelSolvers` in the `CADModel` package** (product `CADModelSolvers`, `PlaneGCSSketchSolver: SketchSolving`), beside `CADModelKernel`, depending on `../CADSolvers`. `CADModel` itself stays free of C++. Cost if wrong: merging it into `CADModelKernel` later is mechanical.
- **Ruling: `RebuildEngine(kernel:sketchSolver:)` and `CADSession(document:kernel:sketchSolver:)` take `(any SketchSolving)? = nil`.** Without a solver every sketch fails with "no sketch solver is available", and extrudes skip. The app, `cadbench` (runner, grader, CLI) and the real-kernel tests pass `PlaneGCSSketchSolver()`. Cost if wrong: a host that forgets the solver sees sketches fail loudly, never wrong geometry.
- **Ruling: entities and constraints carry stored names.** Entities are `point1`, `line1`, `arc1`, `circle1` (per-kind counter, next number above the highest used, never reused within the sketch); constraints are `c1`, `c2`, …. Tools assign names when the caller gives none. Constraints refer to entities by name and to points as `line1.start`, `line1.end`, `arc1.start`, `arc1.end`, `arc1.center`, `circle1.center`, `point1`. Cost if wrong: none; names survive edits, which is what references need.
- **Ruling: the document stores the entities' geometry as the solver's starting guess and never writes the solution back.** Rebuilding the same document always yields the same geometry, which undo and determinism need. Cost if wrong: a large dimension change can make the solver pick another branch (a flipped arc); the agent sees it in the result and can move the guess with `edit_sketch` `update_entities`.
- **Ruling: `fixed` takes an optional `at: [x, y]`** (expressions allowed) that replaces the point's guess before solving, so "this corner at the origin" is one constraint. Without `at` the point stays at its guess. Cost if wrong: none.
- **Ruling: constraint values are `Scalar`s; `angle` values and arc angles are degrees in the document and converted to radians for the solver.** `distance`, `pointLineDistance`, `radius`, `diameter`, `angle` need `value`; others refuse one. Cost if wrong: none.
- **Ruling: sketch states map to feature statuses.** Fully, under- (with DOF) and redundantly constrained sketches are `ok` and still build; over-constrained (`c3, c7 conflict`) and failed solves make the sketch `failed`, and extrudes/revolves using it are `skipped`. Cost if wrong: an agent might ignore a redundant warning; the listing shows it.
- **Ruling: planes.** `XY` (x = X, y = Y, normal +Z), `XZ` (x = X, y = Z, normal −Y), `YZ` (x = Y, y = Z, normal +X), all through the origin; or a planar face of a named body, resolved like any face reference (exactly one face): normal = outward face normal, origin = the global origin projected onto the face plane, x = the first of global X, Y, Z whose projection onto the plane is longer than 0.1, normalised, y = normal × x. `offset` moves the plane along its normal. Cost if wrong: a face sketch's axes may surprise on slanted faces; the sketch tool result states the frame.
- **Ruling: profiles are found in the solved, non-construction lines, arcs and circles.** Endpoints closer than 1e-4 mm are one node. Every node of a loop has exactly two curve ends; a circle is a loop by itself. Chains with a free end are ignored for profiles and listed as open ends; a node where three or more curve ends meet fails extrudes with the node's position and entities. Loops nest by containment (polygonal approximation, arcs sampled at 5° or finer): the regions of "all" are the loops at even depth, each with the loops directly inside it as holes. Crossing or self-intersecting loops are not detected by the model; the kernel's face or validity check fails the extrude. Cost if wrong: an error message less specific than it could be.
- **Ruling: `regions` selects loops by naming any entity of the loop.** The selected loop becomes the outer boundary, with the loops directly inside it as holes, whatever its depth, so `regions: ["circle1"]` on a plate outline with a circle gives the disc. An empty list means all even-depth regions. Cost if wrong: none.
- **Ruling: extrude extents.** `distance d` from the plane to d along the normal (`reversed` flips to −d); `symmetric d` from −d/2 to d/2; `throughAll` spans the target body's bounding box along the normal in both directions with 1 mm margin (needs join, cut or intersect; `reversed` ignored); `upToFace` goes from the plane to a planar face of a named body (`referenceBody`, default the target body) that is parallel to the sketch plane (angle within 1e-6), with the sign of its offset. Cost if wrong: an angled up-to face is refused rather than approximated.
- **Ruling: revolve axes** are a line entity of the same sketch (construction or not), the global `X`, `Y` or `Z` axis through the origin, or a straight edge of a named body (`referenceBody`, default the target body). `angle` defaults to 360; it is degrees in (0, 360]. The profile goes counter-clockwise about the axis direction (line start → end). Cost if wrong: none.
- **Ruling: face names come from geometry, not OCCT history.** OCCTSwift 3.0.0 has no history for prisms or revolutions. After building, the kernel computes the topology: planar faces lying in the start plane (extrude: offset `from`; revolve: the sketch plane, adjacent to a profile edge) are `<F>.start`, those in the end plane are `<F>.end`; every edge lying on a profile curve (midpoint on the curve within 1e-6 mm, in the start plane) names its non-cap adjacent faces `<F>.side[<Sketch>.<entity>]`; anything left is `<F>.face[k]`. Several regions give several `.start` faces, which display as `.start[0]`, `.start[1]`. Cost if wrong: a degenerate profile could leave a side face with a fallback name; tests pin rectangles, circles, arcs, holes and revolves.
- **Ruling: several regions are extruded one by one, named, then fused** (superseded at review; the plan first said `Shape.compound`). Loops that cross are both depth 0 and would otherwise give overlapping solids. Cost if wrong: one boolean per extra region.
- **Ruling: the listing shows a sketch on one line** — `Sketch1  on XY: 4 lines, 1 circle; 1 region; fully constrained  ok` — and `get_sketch` (new read tool, also returned by `add_sketch`/`edit_sketch`) shows the frame, every entity with solved coordinates and every constraint. Cost if wrong: one more tool call to see a sketch.
- **Ruling: the app keeps PlaneGCS unoptimised in Debug.** Typical sketches (≤ 30 entities) solve in milliseconds even unoptimised (measured in Task 10), rebuilds run off the main actor, and optimising one package in an Xcode Debug build needs `unsafeFlags`, which PR 7 ruled out. Cost if wrong: large sketches feel slow in Debug only; Release is unaffected.
- **Ruling: extrude and revolve count as body-creating features when their operation is `newBody`**, exactly like primitives, so `Body<n>` numbering and body-reference repair keep working. Cost if wrong: none.

- **Ruling (execution): faces are named by carrying each curve's midpoint along the sweep** — the planar face perpendicular to the sweep that holds it at the start is `.start`, at the end `.end`, and the face holding it halfway is `.side[…]` — found by point-to-face distance. Matching profile edges missed revolved discs, whose planar faces keep no profile edge. Cost if wrong: O(curves × faces) distance queries per sweep.
- **Ruling (execution): `FeatureError.extent`** carries extent and angle problems, separate from sketch errors. Cost if wrong: none.
- **Ruling (execution): `add_sketch`/`edit_sketch` append the `get_sketch` text to the write report** instead of a separate sketch line. Cost if wrong: longer write results for big sketches.
- **Ruling (execution): a face plane without `body` uses the part's only created body**, else the tool refuses and lists the bodies. Cost if wrong: none.
- **Measured (execution):** a 30-entity sketch rebuilds in 0.04 s in a debug build, which settles the Debug-performance ruling.
- **Ruling (review): removed entity and constraint names are stored in `SketchFeature.retiredNames` (`"retired"` in JSON) and never handed out again**, so `side[Sketch1.line4]` cannot silently land on a new line. Cost if wrong: names keep counting up.
- **Ruling (review): `update_entities` keeps the stored construction flag unless given and refuses a change of entity type.** Cost if wrong: none.
- **Ruling (review): the compiler checks entity kinds (lines, arcs or circles per constraint, `tangentAt` on ends), distinct operands, positive lengths and radii, and non-degenerate or full-turn arcs**, so tools refuse such sketches before writing. Cost if wrong: none; the solver repeats the checks.

## Deferred after the final review

- Removing an entity does not list later features that use it (`regions`, a sketch-line axis, `side[Sketch.entity]` references); they fail at rebuild with their own messages.
- `delete_feature` does not refuse deleting a sketch that an extrude or revolve uses.
- Review Focus 4 has no test for an outward distance cut; a cut that removes nothing is not flagged.
- The prompt says `Extrude1.start` is on the sketch plane; for symmetric and through-all extents it is the cap at the lower offset.
- `edit_sketch` ignores `body` without `plane` on a base-plane sketch.
- Filter expressions in a sketch face plane, an up-to face or an edge axis are not audited like fillet filters.
- Selecting both a loop and its hole in `regions` fuses the hole shut instead of refusing.
- Every solved sketch is drawn, including ones an extrude consumed, on the solid's start face.
- Four pre-existing `CADSessionTests` (their `Gate` blocks a cooperative thread by design) time out under `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`; two pre-existing `DocumentListingTests` expressions exceed the 150 ms type-check limit.

## Review Focus

1. An open or branched profile (a rectangle with one line missing, or a T junction). Expected: the extrude fails naming the open ends or the branch node and its entities; the sketch itself is `ok` with the open ends in `get_sketch`. Pinned in Task 4 (`openChain`, `branchNode`) and Task 6 (`extrudeOpenProfileFails`).
2. An over-constrained sketch used by an extrude. Expected: sketch `failed: over-constrained, c3, c5 conflict` naming constraint names, extrude `skipped: depends on Sketch1`, later independent features build. Pinned in Task 5 (`overConstrainedSkipsExtrude`) and Task 6 (`conflictingConstraintsNamed`).
3. A reference to a sketch entity or constraint that does not exist, or a constraint of the wrong arity/kind. Expected: the sketch fails naming the constraint and the problem; tools refuse before writing. Pinned in Task 3 (`compileErrors`) and Task 8 (`addSketchRefusals`).
4. A cut sketched on a face whose extrude goes the wrong way (outward) with a distance. Expected: no crash; the cut removes nothing and the write result shows the unchanged volume; `throughAll` cuts regardless of direction. Pinned in Task 6 (`throughAllCutFromTopFace`).
5. Renaming a sketch or deleting an entity used by a face reference. Expected: rename rewrites `sketch` fields and `side[Sketch1.…]` names; removing an entity removes the constraints that use it and reports them. Pinned in Task 7 (`renameSketchRewrites`) and Task 8 (`removeEntityDropsConstraints`).

## File Structure

`Packages/CADKernel/Sources/CADKernel/`: `Profile.swift` (new: `ProfilePlane`, `ProfileCurve`, `ProfileRegion`, `Profile`), `Kernel+Sketch.swift` (new: faces from profiles, `extrude`, `revolve`), `ProfileNaming.swift` (new: geometric cap/side naming). Tests: `SketchSolidTests.swift` (new); delete `Kernel.extrudeRectangle` and `ExtrudeTests.swift` (superseded).

`Packages/CADModel/`:

- `Package.swift` (dependency `../CADSolvers`, target/product `CADModelSolvers`, test target `CADModelSolversTests`).
- `Sources/CADModel/`: `Sketch.swift` (new: `SketchFeature`, `SketchPlane`, `SketchEntity`, `SketchConstraint`, `SketchPoint2`), `Sketch+Codable.swift` (new), `SketchBased.swift` (new: `ExtrudeFeature`, `RevolveFeature`, `ExtrudeExtent`, `RevolveAxis`), `SketchSolving.swift` (new: protocol and `SketchSystem`), `SketchCompiler.swift` (new), `SketchProfiles.swift` (new: loops and regions), `SketchFrame.swift` (new), `SketchResult.swift` (new), `PartBuilder+Sketch.swift` (new), `Feature.swift`, `Feature+Codable.swift`, `Part+Bodies.swift`, `PartBuilder.swift`, `GeometryKernel.swift`, `RebuildResult.swift`, `RebuildEngine.swift`, `RebuildEngine+Solids.swift` (modify).
- `Sources/CADModelKernel/OCCTGeometryKernel.swift` (extrude, revolve).
- `Sources/CADModelSolvers/PlaneGCSSketchSolver.swift` (new).
- Tests: `CADModelTests/{SketchCodingTests,SketchCompilerTests,SketchProfilesTests,SketchRebuildTests}.swift`, `FakeKernel.swift`, `FakeSketchSolver.swift`; `CADModelSolversTests/{PlaneGCSSketchSolverTests,SketchIntegrationTests}.swift`.

`Packages/CADAssistantTools/`: `Package.swift` (CADModelSolvers for tests and CLI); `Sources/CADAssistantTools/`: `FeatureSpec.swift`, `FeatureSpec+Sketch.swift` (new), `DocumentListing.swift`, `SketchListing.swift` (new), `ExpressionAudit.swift`, `FeatureLifecycleTools.swift`, `WriteReport.swift`, `CADSession.swift`, `SketchTools.swift` (new: `AddSketchTool`, `EditSketchTool`, `GetSketchTool`), `SketchArguments.swift` (new), `CADTools.swift`, `CADAssistantPrompt.swift`. `CADBench/{Check,Grader,BenchRunner}.swift`, `CADBenchCLI/CADBenchCommand.swift`. Tests: `SketchToolTests.swift`, `SketchFeatureToolTests.swift` (new), `FakeKernel.swift`, `DocumentListingTests.swift`, `Harness.swift`, `RealKernelTests.swift`, bench tests.

App: `Package.swift`, `project.yml`, `3DModellerApp/Views/ContentView.swift`, `Viewport/ViewportScene.swift`, `Viewport/SketchDisplay.swift` (new), `Views/FeatureDisplay.swift`, `Views/FeatureInspectorView.swift`; tests `3DModellerAppTests/SketchDisplayTests.swift` (new), `FeatureDisplayTests.swift`, `AssistantEditingTests.swift`.

Bench: `Bench/tasks/{l-profile,revolved-cup,slotted-plate,profile-height}/`, `Bench/README.md`. Docs: `CLAUDE.md`.

---

### Task 1: Solids from profiles in CADKernel

**Files:** create `Profile.swift`, `Kernel+Sketch.swift`, `ProfileNaming.swift`, `Tests/CADKernelTests/SketchSolidTests.swift`; modify `Kernel.swift` (remove `extrudeRectangle`); delete `ExtrudeTests.swift`.

**Interfaces — Produces:**

```swift
public struct ProfilePlane: Sendable, Hashable {
    public var origin: SIMD3<Double>; public var xAxis: SIMD3<Double>; public var yAxis: SIMD3<Double>
    public var normal: SIMD3<Double> { simd_normalize(simd_cross(xAxis, yAxis)) }
    public init(origin: SIMD3<Double>, xAxis: SIMD3<Double>, yAxis: SIMD3<Double>)
    public func point(_ p: SIMD2<Double>) -> SIMD3<Double>          // origin + x·xAxis + y·yAxis
}
public enum ProfileGeometry: Sendable, Hashable {
    case line(SIMD2<Double>, SIMD2<Double>)
    /// Counter-clockwise or clockwise; `mid` picks the side.
    case arc(center: SIMD2<Double>, radius: Double, start: SIMD2<Double>, mid: SIMD2<Double>, end: SIMD2<Double>)
    case circle(center: SIMD2<Double>, radius: Double)
}
public struct ProfileCurve: Sendable, Hashable { public var name: String; public var geometry: ProfileGeometry }
/// Each loop is ordered so that each curve ends where the next starts.
public struct ProfileRegion: Sendable, Hashable { public var outer: [ProfileCurve]; public var holes: [[ProfileCurve]] }
public struct Profile: Sendable, Hashable { public var plane: ProfilePlane; public var regions: [ProfileRegion] }

extension Kernel {
    /// Sweeps the regions along the plane normal from offset `from` to `to` (mm, `from != to`).
    public static func extrude(_ profile: Profile, from: Double, to: Double, feature: String) throws -> Solid
    /// Revolves the regions by `angle` radians (0 < angle ≤ 2π) about the axis, counter-clockwise about its direction.
    public static func revolve(
        _ profile: Profile, axisOrigin: SIMD3<Double>, axisDirection: SIMD3<Double>, angle: Double, feature: String
    ) throws -> Solid
}
```

Errors: no regions → `.invalidDimensions("the profile has no closed region")`; non-finite or equal `from`/`to`, angle outside (0, 2π], zero axis → `.invalidDimensions(…)`; a wire, face, prism or revolution that OCCT refuses, or a result that is not valid with positive volume → `.operationFailed("build a face from the profile")` / `("extrude the profile")` / `("revolve the profile")`.

Face building (inside the lock): each curve → `Wire.line(from:to:)` / `Wire.arc(start:midpoint:end:)` / `Wire.circle(origin:normal:radius:)` in 3D via `plane.point`; loop → `Wire.join`; region → `Shape.face(outer:holes:)`. Extrude: face translated by `normal·from` (`Shape.translated`), `extruded(by: normal·(to − from))`. Revolve: `revolved(axisOrigin:axisDirection:angle:)` (full 2π uses the full variant). Several regions → `Shape.compound`.

Naming (`ProfileNaming.names(of shape: Shape, curves: [ProfileCurve], plane: ProfilePlane, startOffset: Double, endPlane: (origin: SIMD3<Double>, normal: SIMD3<Double>)?, feature:) -> [[String]]`), computed from `Kernel.topology` of the unnamed solid: caps and sides as in the naming ruling; `onCurve(_ p: SIMD2<Double>, _ g: ProfileGeometry) -> Bool` (segment distance, circle distance plus angular containment for arcs, tolerance 1e-6).

- [ ] **Step 1: failing tests** (`SketchSolidTests`):
  - `rectangleExtrude`: 60×40 rectangle (four lines `S.line1…4`) on XY, 0→10: volume 24000, bounds (0,0,0)…(60,40,10), faces named `F.start` (normal −Z at z 0), `F.end` (+Z at z 10), and `F.side[S.line1]` … `[S.line4]` each once.
  - `plateWithHole`: the rectangle with a circle r 5 at (30, 20) as hole: volume 24000 − π·25·10 (hoisted), a cylinder face named `F.side[S.circle1]` with radius 5.
  - `reversedAndOffset`: from −5 to 5 on XZ (x = X, y = Z, normal −Y): bounds y −5…5, the `F.start` centroid at y = 5 and `F.end` at y = −5.
  - `arcSlot`: two lines and two semicircle arcs (slot 20 long, 8 wide): volume (20·8 + π·16)·h, two cylinder faces named by the arcs.
  - `revolveCupProfile`: a closed L-shaped half section on XZ (x = radius, y = height) revolved 2π about Z: volume π(30²·50 − 27²·46) within 1e-6 relative, faces `R.side[S.line…]` incl. a cylinder r 30, no `.start`/`.end`.
  - `partialRevolve`: a 10×10 square at x 20…30 on XZ revolved π/2 about Z: faces `R.start` and `R.end` exist, volume (π/4)(30² − 20²)·10.
  - `twoRegions`: two disjoint squares → one solid value with two solids, two `.start` faces.
  - `invalidInputs`: no regions, `from == to`, angle 0, angle 7, zero axis all throw `KernelError`.
- [ ] **Step 2: run, expect compile failure** — `xcrun swift test --package-path Packages/CADKernel --scratch-path Packages/CADModel/.build --filter SketchSolid`.
- [ ] **Step 3: implement** as described; remove `extrudeRectangle` and `ExtrudeTests.swift` (the new tests cover prisms).
- [ ] **Step 4: run the whole kernel suite.**
- [ ] **Step 5: commit** `feat(kernel): extrude profiles into named solids`, then `feat(kernel): revolve profiles into named solids`, then `refactor(kernel): drop the rectangle extrusion`.

### Task 2: Sketch-based features in the document

**Files:** create `Sketch.swift`, `Sketch+Codable.swift`, `SketchBased.swift`; modify `Feature.swift`, `Feature+Codable.swift`, `Part+Bodies.swift`; test `SketchCodingTests.swift`.

**Interfaces — Produces:**

```swift
public struct SketchPoint2: Sendable, Hashable, Codable { public var x: Double; public var y: Double }  // JSON [x, y]
public enum SketchBasePlane: String, Sendable, Hashable, Codable, CaseIterable { case xy = "XY", xz = "XZ", yz = "YZ" }
public enum SketchPlane: Sendable, Hashable {
    case base(SketchBasePlane, offset: Scalar = 0)
    case face(body: String, face: GeometryReference, offset: Scalar = 0)
}
public enum SketchGeometry2: Sendable, Hashable {
    case point(SketchPoint2)
    case line(start: SketchPoint2, end: SketchPoint2)
    case circle(center: SketchPoint2, radius: Double)
    /// Degrees, counter-clockwise from startAngle to endAngle.
    case arc(center: SketchPoint2, radius: Double, startAngle: Double, endAngle: Double)
}
public struct SketchEntity: Sendable, Hashable { public var name: String; public var geometry: SketchGeometry2; public var construction: Bool }
public enum SketchConstraintKind: String, Sendable, Hashable, Codable, CaseIterable {
    case coincident, horizontal, vertical, parallel, perpendicular, tangent, tangentAt, equal, distance,
         pointLineDistance, angle, radius, diameter, fixed, pointOnLine, pointOnCircle
}
public struct SketchConstraint: Sendable, Hashable {
    public var name: String; public var kind: SketchConstraintKind
    public var entities: [String]; public var points: [String]
    public var value: Scalar?; public var at: [Scalar]?
}
public struct SketchFeature: Sendable, Hashable { public var plane: SketchPlane; public var entities: [SketchEntity]; public var constraints: [SketchConstraint] }

public enum ExtrudeExtent: Sendable, Hashable {
    case distance(Scalar), symmetric(Scalar), throughAll
    case upToFace(body: String, face: GeometryReference)
}
public struct ExtrudeFeature: Sendable, Hashable {
    public var sketch: String; public var regions: [String]; public var extent: ExtrudeExtent
    public var reversed: Bool; public var operation: SolidOperation
}
public enum RevolveAxis: Sendable, Hashable { case sketchLine(String), x, y, z; case edge(body: String, edge: GeometryReference) }
public struct RevolveFeature: Sendable, Hashable {
    public var sketch: String; public var regions: [String]; public var axis: RevolveAxis
    public var angle: Scalar; public var operation: SolidOperation
}
public enum FeatureKind { …; case sketch(SketchFeature), extrude(ExtrudeFeature), revolve(RevolveFeature) }
extension FeatureKind {
    public var sketchReference: String? { get }                    // extrude/revolve
    public var solidOperation: SolidOperation? { get }             // primitive/extrude/revolve
}
```

JSON:

```json
{"type": "sketch", "plane": {"base": "XY", "offset": 0},
 "entities": [{"name": "line1", "type": "line", "start": [0, 0], "end": [60, 0]},
              {"name": "circle1", "type": "circle", "center": [30, 20], "radius": 5, "construction": true},
              {"name": "arc1", "type": "arc", "center": [0, 0], "radius": 5, "startAngle": 0, "endAngle": 90},
              {"name": "point1", "type": "point", "at": [1, 2]}],
 "constraints": [{"name": "c1", "type": "coincident", "points": ["line1.end", "line2.start"]},
                 {"name": "c2", "type": "distance", "points": ["line1.start", "line1.end"], "value": "width"},
                 {"name": "c3", "type": "fixed", "points": ["line1.start"], "at": [0, 0]}]}
{"type": "sketch", "plane": {"body": "Body1", "face": {"name": "Box1.top"}, "offset": 2}, …}
{"type": "extrude", "sketch": "Sketch1", "regions": [], "extent": {"type": "distance", "value": 10}, "reversed": false,
 "operation": {"mode": "newBody"}}
{"type": "extrude", …, "extent": {"type": "upToFace", "body": "Body1", "face": {"name": "Box1.top"}}}
{"type": "revolve", "sketch": "Sketch1", "regions": [], "axis": {"line": "line5"}, "angle": 360, "operation": {…}}
axis forms: {"line": "line5"} | {"global": "Z"} | {"body": "Body1", "edge": {"name": "…"}}
```

Omitted keys decode to defaults (`construction` false, `offset` 0, `regions` [], `reversed` false, `angle` 360, `operation` newBody, `entities`/`points` []).

`Part+Bodies` / `Feature.swift` updates: `createsNewBody` and `affectedBody` use `solidOperation`; `bodyReferences`/`renameBodyReferences` include a face plane's body, `upToFace` body, axis edge body and the operation target; `geometryReferences` include the plane face, up-to face and axis edge; `renameFeatureReferences(old, to:)` also rewrites `sketch == old`. A sketch feature affects no body.

- [ ] **Step 1: failing tests** (`SketchCodingTests`): round trip of a sketch with all four entity kinds and every constraint field, a face plane, extrude with each extent, revolve with each axis form; decoding the minimal forms gives the defaults; `createdBodies` counts a newBody extrude and not a sketch or a cut extrude; `bodyReferences` of a face-plane sketch is `["Body1"]`; `renameFeatureReferences("Sketch1", to: "Base")` changes `sketch` and `side[Sketch1.line1]` in a fillet edge name.
- [ ] **Step 2–4:** run `xcrun swift test --package-path Packages/CADModel --filter SketchCoding`, implement, run the CADModel suite (fix switch exhaustiveness in `PartBuilder` with a temporary `.failed(.kernel("not built yet"))` branch that Task 5 replaces; CADAssistantTools and the app are updated in their own tasks and must still compile: add the three cases to `FeatureSpec.init(_ kind:)`, `DocumentListing.summary`, `scalarFields`, `FeatureType`, `FeatureDisplay` with minimal text in this task).
- [ ] **Step 5: commit** `feat(model): describe sketches, extrudes and revolves`.

### Task 3: Solver protocol and sketch compilation

**Files:** create `SketchSolving.swift`, `SketchCompiler.swift`; tests `SketchCompilerTests.swift`, `FakeSketchSolver.swift`.

**Interfaces — Produces:**

```swift
public enum SketchSystem {}   // namespace
public struct SolverSketch: Sendable, Hashable { public var entities: [SolverEntity]; public var constraints: [SolverConstraint] }
public struct SolverEntity: Sendable, Hashable { public var geometry: SolverGeometry; public var construction: Bool }
public enum SolverGeometry: Sendable, Hashable {   // radians
    case point(SIMD2<Double>), line(SIMD2<Double>, SIMD2<Double>), circle(center: SIMD2<Double>, radius: Double)
    case arc(center: SIMD2<Double>, radius: Double, startAngle: Double, endAngle: Double)
}
public enum SolverPointRef: Sendable, Hashable { case point(Int), start(Int), end(Int), center(Int) }
public enum SolverConstraint: Sendable, Hashable {  // mirrors CADSolvers.SketchConstraint, radians
    case coincident(SolverPointRef, SolverPointRef), horizontal(Int), vertical(Int), parallel(Int, Int)
    case perpendicular(Int, Int), tangent(Int, Int), tangentAt(SolverPointRef, SolverPointRef), equal(Int, Int)
    case distance(SolverPointRef, SolverPointRef, Double), pointLineDistance(SolverPointRef, line: Int, Double)
    case angle(Int, Int, Double), radius(Int, Double), diameter(Int, Double), fixed(SolverPointRef)
    case pointOnLine(SolverPointRef, line: Int), pointOnCircle(SolverPointRef, curve: Int)
}
public enum SolverState: Sendable, Hashable { case fullyConstrained, underConstrained(dof: Int), overConstrained(conflicting: [Int]), redundant([Int]), failed }
public struct SolverSolution: Sendable, Hashable { public var entities: [SolverEntity]; public var state: SolverState; public var degreesOfFreedom: Int }
public struct SketchSolvingError: Error, Sendable, Equatable, CustomStringConvertible { public let description: String }
public protocol SketchSolving: Sendable {
    func solve(_ sketch: SolverSketch) throws(SketchSolvingError) -> SolverSolution
}

enum SketchCompiler {
    /// Validates names and arity, evaluates values (degrees → radians), applies `fixed … at`.
    static func compile(_ sketch: SketchFeature, parameters: ParameterTable) throws(FeatureError) -> SolverSketch
    /// The solved entities back in document terms (degrees), keeping names and construction flags.
    static func entities(_ solution: SolverSolution, of sketch: SketchFeature) -> [SketchEntity]
}
public enum SketchSolveState: Sendable, Equatable, CustomStringConvertible {
    case fullyConstrained, underConstrained(dof: Int), overConstrained(conflicting: [String]), redundant([String]), failed
    // "fully constrained", "under-constrained, 2 degrees of freedom", "over-constrained, c3, c5 conflict",
    // "redundant: c7", "solve failed"
}
FeatureError += .sketch(String)
```

Compile errors (`FeatureError.sketch`): duplicate entity/constraint names; unknown entity `'line9'` (lists the entities); a point ref with an unknown role (`line1.center` → "line1 has start and end"); wrong count (`c2 (distance) needs 2 points`, `c4 (horizontal) needs 1 entity`); a value where none applies or none where one is needed; `at` on anything but `fixed` or not two values; expression errors (`c2 value: …`).

- [ ] **Step 1: failing tests**: `compilesRectangle` (four lines, coincidences, horizontal/vertical, fixed at (0,0) moves the guess of `line1.start` to (0, 0), distance `"width"` with parameter width = 60 → `.distance(.start(0), .end(0), 60)`); `anglesInRadians` (arc 0…90 → 0…π/2, angle 30 → π/6); `solutionBackToDegrees`; `compileErrors` (parameterised over the errors above, each message containing the constraint name); `stateNames` maps indices to names.
- [ ] **Step 2–4:** run, implement, run.
- [ ] **Step 5: commit** `feat(model): compile sketches for a solver`.

### Task 4: Loops and regions

**Files:** create `SketchProfiles.swift`; test `SketchProfilesTests.swift`.

**Interfaces — Produces:**

```swift
public struct SketchLoop: Sendable, Equatable { public var curves: [SketchCurve]; public var depth: Int; public var area: Double }
public struct SketchCurve: Sendable, Hashable { public var entity: String; public var geometry: SketchCurveGeometry }
public enum SketchCurveGeometry: Sendable, Hashable {   // oriented along the loop
    case line(SIMD2<Double>, SIMD2<Double>)
    case arc(center: SIMD2<Double>, radius: Double, start: SIMD2<Double>, mid: SIMD2<Double>, end: SIMD2<Double>)
    case circle(center: SIMD2<Double>, radius: Double)
}
public struct SketchRegion: Sendable, Equatable { public var outer: [SketchCurve]; public var holes: [[SketchCurve]] }
public struct SketchProfiles: Sendable, Equatable {
    public var loops: [SketchLoop]
    public var openEnds: [String]          // "line3.end (12, 5)"
    public var branchPoints: [String]      // "(10, 0): line1.end, line2.start, line5.start"
    public init(_ entities: [SketchEntity])
    /// All even-depth regions when `selection` is empty; otherwise the loops containing the named entities.
    public func regions(selecting selection: [String]) throws(FeatureError) -> [SketchRegion]
}
```

- [ ] **Step 1: failing tests**: rectangle → one loop, depth 0, area 2400, region with no holes; rectangle + inner circle → circle depth 1 is a hole; plus a circle inside that circle (depth 2) → two regions; `regions(selecting: ["circle1"])` → the disc with the inner circle as its hole; slot of lines and arcs in scrambled order and directions → one loop, curves chained end to start; construction lines and points ignored; `openChain` (three lines of a rectangle) → no loops, open ends listed; `branchNode` (rectangle plus a line from a corner) → `regions` throws naming the node; selecting an unknown or open entity throws naming it; endpoints 5e-5 apart join.
- [ ] **Step 2–4:** run, implement (node merge by tolerance, walk degree-2 nodes, arc orientation from the traversal direction, polygon sampling for area and containment via ray casting on a sample point of each loop), run.
- [ ] **Step 5: commit** `feat(model): find closed profiles in sketches`.

### Task 5: Rebuilding sketches, extrudes and revolves

**Files:** create `SketchFrame.swift`, `SketchResult.swift`, `PartBuilder+Sketch.swift`; modify `GeometryKernel.swift`, `PartBuilder.swift`, `RebuildResult.swift`, `RebuildEngine.swift`, `RebuildEngine+Solids.swift`, `CADModelKernel/OCCTGeometryKernel.swift`, `Tests/CADModelTests/FakeKernel.swift`, CADAssistantTools test fake; tests `SketchRebuildTests.swift`.

**Interfaces — Produces:**

```swift
public struct SketchFrame: Sendable, Hashable {
    public var origin: SIMD3<Double>; public var xAxis: SIMD3<Double>; public var yAxis: SIMD3<Double>
    public var normal: SIMD3<Double> { get }
    public func point(_ p: SIMD2<Double>) -> SIMD3<Double>
    public static func base(_ plane: SketchBasePlane, offset: Double) -> SketchFrame
    public static func face(_ face: FaceDescriptor, offset: Double) -> SketchFrame?   // nil unless planar
}
public struct SketchProfile: Sendable, Equatable { public var frame: SketchFrame; public var regions: [SketchRegion] }
public protocol GeometryKernel { …
    /// Curve names in `profile` are already qualified (`Sketch1.line3`).
    func extrude(_ profile: SketchProfile, from: Double, to: Double, feature: String) throws -> Body
    func revolve(_ profile: SketchProfile, axisOrigin: SIMD3<Double>, axisDirection: SIMD3<Double>,
                 angleDegrees: Double, feature: String) throws -> Body
}
public struct SketchResult: Sendable, Equatable, Identifiable {
    public let id: UUID                    // the sketch feature's id
    public let name: String
    public let frame: SketchFrame
    public let entities: [SketchEntity]    // solved (or the input when the solve failed)
    public let state: SketchSolveState
    public let degreesOfFreedom: Int
    public let profiles: SketchProfiles
}
public struct PartResult { …; public let sketches: [SketchResult] }
extension RebuildResult { public func sketch(id: UUID) -> SketchResult? }
public struct RebuildEngine<Kernel> { public init(kernel: Kernel, sketchSolver: (any SketchSolving)? = nil) }
```

PartBuilder: `.sketch` resolves the frame (face planes: `body(named:)`, `select(face,…)` must give exactly one planar face → "the sketch plane must be one planar face"), compiles, solves (`solver == nil` → `.sketch("no sketch solver is available")`), records a `SketchResult` and remembers the sketch by name; over-constrained/failed → status failed and later users skip. `.extrude`/`.revolve`: `sketch(named:)` (unknown → `.sketch("no sketch named 'X' comes before this feature")`, failed → skipped), `profiles.regions(selecting:)`, extent → `(from, to)`, qualify curve names with the sketch name, kernel call, then the operation exactly like primitives (shared helper `combine(_ solid:, operation:, newBody:, feature:)`).

- [ ] **Step 1: failing tests** (fake kernel + `FakeSketchSolver` that returns the input with a configurable state):
  - `extrudeCallsKernel`: sketch on XY + extrude distance 10 → fake records `extrude 1 regions from 0 to 10 Extrude1` and curve names `Sketch1.line1…4`; `Body1` exists.
  - `reversedSymmetric`: reversed distance 10 → from 0 to −10; symmetric 10 → −5…5.
  - `throughAll`: cut through all into a box 0…6 in z from a sketch at z 6 → from −7 to 1 (bounds ± 1 margin, relative to the plane).
  - `upToFace`: sketch on XY, up to `Box1.top` (z 6) → 0…6; a face not parallel fails.
  - `faceFrame`: sketch on `Box1.top` (z 6) offset 2 → frame origin (0, 0, 8), x = X, y = Y; on `Box1.right` → x = Y, y = Z.
  - `overConstrainedSkipsExtrude`: fake state `overConstrained([1])` → sketch `failed: over-constrained, c2 conflict`, extrude `skipped: depends on Sketch1`, an independent box after it is ok.
  - `noSolver`: engine without a solver → sketch failed "no sketch solver is available".
  - `revolveAxes`: axis sketch line (construction line from (0,0) to (0,10) on XZ → origin (0,0,0), direction (0,0,1)), global Z, body edge; angle 90 passed as degrees.
  - `sketchResultsReported`: `PartResult.sketches` has the solved entities and state.
- [ ] **Step 2–4:** run, implement (fake: extrude → a fake body with bounds from the profile's frame-mapped points and the offsets; revolve → bounds of the swept radius), run CADModel and CADAssistantTools suites.
- [ ] **Step 5: commit** `feat(model): rebuild sketches through a solver`, then `feat(model): build extrude features from sketch profiles`, then `feat(model): build revolve features from sketch profiles`.

### Task 6: PlaneGCS adapter and integration

**Files:** `Packages/CADModel/Package.swift`; create `Sources/CADModelSolvers/PlaneGCSSketchSolver.swift`, `Tests/CADModelSolversTests/{PlaneGCSSketchSolverTests,SketchIntegrationTests}.swift`; `OCCTGeometryKernel.swift` (extrude/revolve mapping to `CADKernel.Profile`).

```swift
public struct PlaneGCSSketchSolver: SketchSolving {
    public init()
    public func solve(_ sketch: SolverSketch) throws(SketchSolvingError) -> SolverSolution
}
```

- [ ] **Step 1: failing tests**:
  - Adapter: every constraint kind maps (a rectangle solves fully; `SketchSolverError.invalidConstraint(index: 2, …)` becomes a `SketchSolvingError` mentioning index 2).
  - Integration (real kernel + solver): `plateFromSketch` (fully constrained 60×40 rectangle with parameter-driven sizes and a hole circle, extrude 6 → volume 60·40·6 − π·2.75²·6, face `Extrude1.side[Sketch1.circle1]` exists, a fillet on `parallel Z and farthest +X` builds); `parameterChangeResolves` (width 60 → 80 changes the volume); `revolveCup`; `throughAllCutFromTopFace` (box, sketch on `Box1.top` with a circle, cut throughAll → a through hole: volume and `find`-style face `Cut1.side[Sketch1.circle1]` on Body1); `extrudeOpenProfileFails`; `conflictingConstraintsNamed` (second width → `over-constrained, …` naming constraint names); `tangentAtArcSlot` (slot with `tangentAt` joints solves fully and extrudes); `debugTiming` records the time of a 30-entity sketch (asserts < 2 s).
- [ ] **Step 2–4:** run `xcrun swift test --package-path Packages/CADModel --filter CADModelSolversTests`, implement, run the whole CADModel suite.
- [ ] **Step 5: commit** `feat(model): solve sketches with PlaneGCS`, `test(model): build solids from solved sketches`.

### Task 7: Extrude and revolve in the feature tools, listing, audit, rename

**Files:** `FeatureSpec.swift`, `FeatureSpec+Sketch.swift` (new), `DocumentListing.swift`, `SketchListing.swift` (new), `ExpressionAudit.swift`, `FeatureLifecycleTools.swift`, `WriteReport.swift`; tests `SketchFeatureToolTests.swift` (new), `DocumentListingTests.swift`.

- `FeatureSpec.types` += `extrude`, `revolve`; keys += `sketch`, `regions`, `extent` (`distance` default, `symmetric`, `throughAll`, `upToFace`), `reversed`, `face`, `axis` (`X`/`Y`/`Z`, a sketch line name, or an edge name/filter), `referenceBody`, `angle` (dimension); `distance` reused. `sketch` features are not accepted by add_feature ("use add_sketch").
- Listing lines:
  - `Sketch1  on XY: 4 lines, 1 circle, 9 constraints; 1 region; fully constrained  ok` (state and region count only when built; `on Box1.top of Body1, offset 2`).
  - `Extrude1  extrude Sketch1 10 → Body1  ok`, `… regions circle1 symmetric 20`, `… through all, cut Body1 → Body1`, `… up to Box2.top of Body2`, `… 10 reversed`.
  - `Revolve1  revolve Sketch1 about line5 360°, join Body1 → Body1`.
- Audit: sketch offset, constraint values and `at`, extrude distance, revolve angle.
- Rename: notes also for `sketch` fields ("Extrude1 now uses sketch Base (was Sketch1)").
- WriteReport: after the focus status, for a focus sketch: `Sketch1: fully constrained; 1 region` or open ends / branch points.
- [ ] **Step 1: failing tests**: add extrude with each extent; refusals (missing sketch, `throughAll` with newBody, `angle` on extrude, `axis` missing on revolve, `type: sketch`); edit extrude distance keeps the rest; listing lines above; audit refuses `distance: "nope"`; `renameSketchRewrites`.
- [ ] **Step 2–4:** run `xcrun swift test --package-path Packages/CADAssistantTools --filter "SketchFeatureTool|DocumentListing"`, implement, run the suite.
- [ ] **Step 5: commit** `feat(tools): add extrude and revolve to the feature tools`, `feat(tools): list sketches with their solve state`.

### Task 8: add_sketch, edit_sketch, get_sketch; solver wiring; prompt

**Files:** `SketchTools.swift`, `SketchArguments.swift` (new), `CADSession.swift` (`sketchSolver:`), `CADTools.swift`, `CADAssistantPrompt.swift`; tests `SketchToolTests.swift`, `Harness.swift`, `RealKernelTests.swift`.

```
add_sketch(part?, name?, before?, after?, plane: "XY"|"XZ"|"YZ"|<face name or filter>, body?, offset?,
           entities: [{name?, type: point|line|circle|arc, at|start,end|center,radius|center,radius,startAngle,endAngle, construction?}],
           constraints: [{name?, type, entities?, points?, value?, at?}])
edit_sketch(sketch, part?, plane?, body?, offset?, add_entities?, update_entities?, remove_entities?,
            add_constraints?, remove_constraints?, set_values?: {c2: 40})
get_sketch(sketch, part?)
```

`get_sketch` text: `Sketch1 on XY (origin (0, 0, 0), x (1, 0, 0), y (0, 1, 0)): fully constrained; 1 region`, then `entities:` lines `line1  line (0, 0) to (60, 0)`, `circle1  circle centre (30, 20) r=5  construction`, then `constraints:` lines `c1  coincident line1.end, line2.start`, `c5  distance line1.start, line1.end = width (60)`, then open ends / branch points. add/edit return the write report followed by this text.

- [ ] **Step 1: failing tests**: add a rectangle sketch with auto names (`line1…4`, `c1…`) → listing line, result contains `get_sketch` text; `addSketchRefusals` (unknown type, line without end, constraint on `line9`, bad plane, face plane without body when several bodies — body defaults to the only body); edit: add a circle and its radius, `set_values` on `c5`, `removeEntityDropsConstraints` (reports `removed c7, c8 with circle1`), `update_entities` moves a guess, remove unknown constraint refused; real kernel + PlaneGCS: add_sketch + add_feature extrude builds a plate; `find_geometry` on it lists `Extrude1.side[Sketch1.line1]`.
- [ ] **Step 2–4:** run, implement, run.
- [ ] Prompt: a "## Sketches" section — planes and their axes, entity/point names, constraint list with arity, `fixed at`, fully constrain (DOF 0: two coordinates per point, … ; fix one point, dimension every size, horizontal/vertical), prefer `tangentAt` for tangent joints over coincident + tangent, extrude/revolve options, face names `Extrude1.side[Sketch1.line3]`, `.start`/`.end`, cutting into a face needs `reversed` or `throughAll`.
- [ ] **Step 5: commit** `feat(tools): add sketches through the assistant tools`, `feat(tools): pass a sketch solver to the session`, `docs(tools): teach the assistant to sketch`.

### Task 9: Bench

**Files:** `Check.swift` (`FeatureType` += sketch, extrude, revolve), `Grader.swift`, `BenchRunner.swift`, `CADBenchCommand.swift` (`sketchSolver:`), `Package.swift` (CADModelSolvers for CLI and tests), tasks, `TaskGradingTests.swift`, `Bench/README.md`.

Tasks:

- `l-profile` (build): L profile on XY, outer 40 (X) × 30 (Y), legs 8 thick, extruded 25 along +Z from z 0: volume (40·8 + 22·8)·25 = 12400; checks gate, bodyCount 1, bbox, volume, featureCount sketch ≥ 1, extrude ≥ 1, IoU 0.999.
- `revolved-cup` (build): cup on the Z axis, outer radius 30, height 50, wall 3, bottom 4, bottom at z 0, from one revolved sketch: volume π(30²·50 − 27²·46); checks incl. revolve ≥ 1.
- `slotted-plate` (build): plate 80×40×6 at the origin with a through slot centred at (40, 20), 28 long overall along X, 8 wide, made from a sketch: volume 80·40·6 − (20·8 + π·16)·6; checks incl. sketch ≥ 1.
- `profile-height` (modify): seed = L-profile whose sketch dimensions use parameters `width`, `height`, `leg`; prompt: make the profile 45 mm tall by changing its height parameter; checks parameter height = 45, volume, bbox, unchangedExcept parameters [height].

Wrong solutions: `lProfileTooThick` (volume), `cupWithoutBottom` (volume), `slotAsRectangle` (volume), `heightEditedInSketch` (parameter height).

- [ ] Steps: write references by hand with fully constrained sketches, compute volumes, grade them in `TaskGradingTests`, prove the wrong solutions fail the named checks, update README tables; commit `feat(bench): grade documents with a sketch solver`, `feat(bench): add sketch tasks`.

### Task 10: App

**Files:** `Package.swift`, `project.yml` (product `CADModelSolvers`), `ContentView.swift`, `Viewport/SketchDisplay.swift` (new), `ViewportScene.swift`, `FeatureDisplay.swift`, `FeatureInspectorView.swift`, `ContentView.swift` (pass sketch result); tests `SketchDisplayTests.swift`, `FeatureDisplayTests.swift`, `AssistantEditingTests.swift`.

```swift
enum SketchDisplay {
    struct Segment: Equatable { var start: SIMD3<Float>; var end: SIMD3<Float>; var construction: Bool }
    /// Model-space segments (mm): lines as one segment, arcs and circles every 10° or finer; construction entities
    /// dashed (every other piece of a line split into 2 mm pieces), points as a small cross.
    static func segments(of sketch: SketchResult) -> [Segment]
}
```

`ViewportScene.show` adds a `sketches` entity: each segment a thin box (0.3 mm square section in scene metres) oriented along the segment, solid entities in a sketch colour, construction in a dimmer grey. Sketches whose feature is suppressed are not in the result and are not drawn.

FeatureDisplay: sketch title "Sketch", symbol `pencil.and.outline`, properties Plane, Entities (count by kind), Constraints (count); extrude "Extrude" (`arrow.up.square`) with Sketch, Regions, Extent, Operation; revolve "Revolve" (`arrow.triangle.2.circlepath`) with Sketch, Axis, Angle, Operation. Inspector: for a sketch, a "Sketch" section with the solve state and read-only lists of entities and constraints.

- [ ] Steps: failing app tests (segments of a rectangle on XY are four at z 0; an XZ circle lies at y 0 and has ≥ 36 segments; construction lines are dashed; display properties), implement, `xcodegen generate`, `xcodebuild … test` with derived data in the scratchpad, record the Debug timing ruling (measure a 30-entity solve through the app test host), commits `build(app): link the sketch solver`, `feat(app): draw sketches in the viewport`, `feat(app): show sketch features in the outline and inspector`.

### Task 11: Docs, CI, final review

- [ ] `CLAUDE.md`: CADModelSolvers, sketches in the architecture. CI already tests `CADModel` (its test targets now include CADModelSolversTests) and `CADSolvers`; no new step. Commit `docs: describe sketches`.
- [ ] Clean `xcrun swift test --package-path <pkg> --scratch-path <scratchpad>/clean` for CADKernel, CADModel, CADAssistantTools; long-expression check with `-Xswiftc -Xfrontend -Xswiftc -warn-long-expression-type-checking=150`; strict pool run.
- [ ] Fresh `opus` reviewer over `git merge-base cad/07-sketch-solver HEAD..HEAD`; one fix pass for Critical/Important; ledger updated.

## Self-review

- Spec coverage: sketch feature with plane/offset, entities incl. construction, the solver's constraints, solve on every rebuild with states (Tasks 2, 3, 5, 6); closed loops → profiles incl. nested (Task 4); extrude/revolve with operations (Tasks 1, 5, 6); naming `Extrude1.side[Sketch1.line3]`, `.start`, `.end` working with references and filters (Tasks 1, 6, 8); `add_sketch`/`edit_sketch`, extrude/revolve through `add_feature`/`edit_feature`, listing, prompt (Tasks 7, 8); display (Task 10); bench growth (Task 9).
- Types: `SketchFeature`, `SketchEntity`, `SketchConstraint`, `SolverSketch`, `SketchProfiles`, `SketchRegion`, `SketchCurve`, `SketchProfile`, `SketchFrame`, `SketchResult`, `SketchSolveState`, `PlaneGCSSketchSolver` keep these names in Tasks 2–10. The kernel's `Profile`, `ProfileRegion`, `ProfileCurve`, `ProfilePlane` stay inside `CADKernel`/`CADModelKernel`.
