# CAD 10: Assembly Solver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assemblies hold joints (fixed, revolute, slider, cylindrical, ball, planar) between frames on instance faces. Every rebuild solves them with FreeCAD's OndselSolver and places the non-grounded instances where the joints put them. Agents add, edit and delete joints and see each joint's status. The app lists joints and shows solved placements. `cadbench` grades joint-based assemblies.

**Architecture:** `Packages/CADSolvers` gains two targets. `OndselSolver` is FreeCAD's OndselSolver, vendored unmodified at a pinned commit. `COndselSolver` is a C shim that builds an `ASMTAssembly` the way FreeCAD's Assembly workbench does, runs `runPreDrag`, and catches every exception. The Swift API `AssemblySolver` validates input, solves, checks every joint geometrically on the result, and retries once from a start where the joint frames coincide. `CADModel` gets `Joint` in `Assembly.joints` and an `AssemblySolving` protocol, which the new adapter `OndselAssemblySolver` in `CADModelSolvers` implements. Rebuild steps:

1. Place the instances at their document placements.
2. Resolve each joint's frames on the part's own topology.
3. Solve.
4. Move the non-grounded instances to the solved placements (kernel transform, then metrics).
5. Report per-joint statuses in `AssemblyResult`.

The tools add `add_joint`, `edit_joint` and `delete_joint`, joint lines in the listing, and joint changes and moved instances in write reports. The bench gains `jointsSatisfied` and `instancePosition` checks and three tasks.

**Tech Stack:** Swift 6 (tools 6.1), Swift Testing, C++23 (`cxx2b`), OndselSolver `4be80eef02a3486cda0d78f3ccbb308d207a9639` (github.com/FreeCAD/OndselSolver, main, 2026-09-19, LGPL-2.1), `simd`, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md`: decision "Constraint solvers"; sections "Document" (assembly joints), "Rebuild" (joint states), "Agent tools" (`add_joint`, `edit_joint`) and "Assemblies and motion" (solving part only); PR-stack row 10. Previous layers: `docs/superpowers/plans/2026-09-26-cad-07-sketch-solver.md` (vendoring pattern), `-08-sketches.md` (solver adapter pattern) and `-09-assemblies.md` (instances, frames).

## Global Constraints

- macOS 26, Apple Silicon only, Swift 6 strict concurrency. Use `xcrun swift`, never bare `swift`.
- Only `CADKernel` imports OCCTSwift. Only `CADSolvers` contains C++ solver code. `CADModel` stays pure Swift and reaches the solver only through `AssemblySolving`.
- No C++ exception may reach Swift. Every failure is a typed error or a status. No `unsafeFlags`.
- Millimetres and degrees in the document, tools and listing.
- The document format stays 1. `joints` is decoded with `decodeIfPresent`.
- Tests use Swift Testing and never block a cooperative thread. They must finish under `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`.
- Hoist long expressions inside `#expect` into typed `let`s.
- Commits are semantic, one concern each, with no "and" in the subject and no co-author lines. Comments only state a non-obvious why.
- No two targets in one package may differ only by case. Clean builds and derived data go to the scratchpad and are deleted afterwards.

## Research: how FreeCAD drives OndselSolver

`src/Mod/Assembly/App/AssemblyObject.cpp` (FreeCAD main) solves in these steps:

1. `makeMbdAssembly()` creates an `ASMTAssembly` named `OndselAssembly`.
2. `fixGroundedParts()` adds one assembly-level `ASMTMarker` at each grounded part's placement, a `FixingMarker` at identity on the part, and an `ASMTFixedJoint` between them.
3. `getMbDData` / `makeMbdPart` create each part as an `ASMTPart`:
   - position and rotation matrix set to the part's global placement (rotation passed as rows);
   - an `ASMTPrincipalMassMarker` with mass 1, density 1 and moments of inertia (1, 1, 1).
4. `handleOneSideOfJoint` adds each joint's marker to its part in part coordinates (`part_global_plc.inverse() * jcs_global`). `makeMbdJointOfType` then builds `ASMTFixedJoint`, `ASMTRevoluteJoint`, `ASMTCylindricalJoint`, `ASMTTranslationalJoint` (slider), `ASMTSphericalJoint` or `ASMTPlanarJoint`. Markers are named by path: `/OndselAssembly/<part>/<marker>`.
5. Parts that are not connected to a grounded part are left out (`removeUnconnectedJoints`). With nothing grounded, the solve is refused.
6. `mbdAssembly->runPreDrag()` runs inside `try/catch` for `std::exception` and `...`. The new placements are read back with `getPosition3D` and the rotation.
7. `updateSolveStatus` walks `mbdSystem->jointsMotionsDo`/`constraintsDo`. A joint is redundant when a constraint's `constraintSpec()` starts with `Redundant`.

A spike measured these behaviours:

- **Direction-cosine constraints.** They only demand perpendicular axes (`IzJx = IzJy = 0`), so a revolute is satisfied with antiparallel z axes, and a fixed joint with any of four 180° flips. The solve stays on the branch nearest its start.
- **Singular start.** A start 90° off, such as a fixed joint whose part starts rotated 90° about Y, flags constraints redundant and "succeeds" with the joint unsatisfied.
- **Conflicts.** Two conflicting fixed joints solve. The first joint's Z constraint is flagged redundant and is left unsatisfied.
- **Redundant pair.** A revolute plus a cylindrical joint on the same axis throws `SimulationStoppingError("iterNo > iterMax")` from a rough start.
- **Nothing grounded.** The bodies drift and rotate arbitrarily.
- **Logging.** The solver prints `MbD: …` lines on every iteration and `Time = 0` to `std::cout`.
- **Build.** The CMake source list compiles under SwiftPM (C++23, `NDEBUG`) in about 40 s in debug. It gives six `-Wshorten-64-to-32` warnings in five files: `AbsConstraint.cpp`, `AtPointConstraintIqcJqc.cpp`, `DirectionCosineConstraintIqcJqc.cpp`, `TranslationConstraintIqcJqc.cpp` and `SymbolicParser.cpp`.

## Rulings

- **Ruling: OndselSolver is vendored unmodified, from the CMake source list.** The `ONDSELSOLVER_SRC` and `ONDSELSOLVER_HEADERS` files, every other `.h` of the directory (some listed `.cpp` files include unlisted headers), and `LICENSE` go under `Sources/OndselSolver/include/OndselSolver/` with a `module.modulemap` that `requires cplusplus`. `ASMTAtPointJoint.cpp`, `ASMTInLineJoint.cpp`, `Functions.cpp`, `StepFunction.cpp` and `Transitions.cpp` are not in the CMake list and are not copied. `Scripts/vendor-ondselsolver.sh` reproduces the tree from the pinned commit. Upstream is `FreeCAD/OndselSolver`; the Ondsel-Development repository is archived. Cost if wrong: a later OndselSolver that needs one of the unlisted files fails to link; rerun the script with it.
- **Ruling: the five narrowing-warning files compile through a wrapper instead of directly.** `Package.swift` excludes them from the target. `Sources/OndselSolver/NarrowingWrappers.cpp` (ours) pushes `#pragma clang diagnostic ignored "-Wshorten-64-to-32"` and `#include`s each of them. The vendored files stay unmodified and no flag is unsafe. Cost if wrong: a new warning in an update shows up in the build log; add it to the wrapper.
- **Ruling: the shim mirrors FreeCAD.** It builds:
  - one `ASMTPart` per body, with FreeCAD's mass marker;
  - one grounding `ASMTFixedJoint` per grounded body, to an assembly marker at its placement;
  - one marker per joint side, in body coordinates;
  - one `ASMT*Joint` per joint.

  It then calls `runPreDrag()` and reads each part's `position3D` and `rotationMatrix`. The `ASMT*Joint` classes are the six named above: slider is `ASMTTranslationalJoint`, ball is `ASMTSphericalJoint`. Per joint it reports the number of constraints and of redundant constraints. Cost if wrong: none found; the adapter is small.

- **Ruling: solves are serialised by one process-wide mutex in the shim, and `std::cout` is muted during a solve** (`rdbuf` swapped to a null buffer, then restored). OndselSolver's thread safety is unverified, and it logs every iteration to stdout. The mute can race with another thread writing to `std::cout` in the same window, and only C++ code does that. In this app that is OCCT's rare messages, which run under their own lock. Cost if wrong: a lost or misplaced OCCT console line.
- **Ruling: `CADSolvers` judges joints geometrically after the solve instead of trusting OndselSolver's success.** Direction matters in this judgement: a revolute needs the z axes pointing the same way, not merely parallel. For each joint, with frames A and B in world coordinates:
  - fixed: origins coincide, z·z′ = 1 and x·x′ = 1;
  - revolute: origins coincide and z·z′ = 1;
  - slider: B's origin lies on A's z line, z·z′ = 1 and x·x′ = 1;
  - cylindrical: B's origin lies on A's z line and z·z′ = 1;
  - ball: origins coincide;
  - planar: (o′ − o)·z = 0 and z·z′ = 1.

  The tolerances are 1e-6 mm for distances and 1e-9 on 1 − cos. Cost if wrong: a flipped branch reads as failed rather than as a quiet wrong result.

- **Ruling: one retry.** If the first solve, from the given placements, throws or leaves a joint unsatisfied, the solver solves again from "coincident starts". It walks the joints breadth-first from the grounded bodies. A body not yet placed, joined to a placed one, starts where its joint frame coincides exactly with the other's: T_B = F_A · L_B⁻¹. The attempt with fewer unsatisfied joints wins; on a tie the first attempt wins. `AssemblySolution.attempts` records 1 or 2. Cost if wrong: for a revolute or slider, a retry resets the free rotation or position to "x axes aligned" or "origins coincident" rather than the guess.
- **Ruling: per-joint status in `CADSolvers`:**
  - `satisfied`;
  - `redundant` (satisfied, but some of its constraints are flagged redundant);
  - `conflicting` (unsatisfied, with redundant constraints flagged in this joint or another);
  - `unsatisfied(distance:angle:)` (the worst offset in mm and the worst axis angle in radians).

  `AssemblySolution.failure` carries the exception text when both attempts threw. In that case the placements are the input ones and every joint is judged at those placements. Cost if wrong: none.

- **Ruling: validation before any C++ runs.** `AssemblySolverError.invalidBody(index:reason:)` or `.invalidJoint(index:reason:)` is raised for:
  - a non-finite number;
  - a rotation that is not orthonormal with determinant +1 (tolerance 1e-9);
  - a joint body index out of range;
  - a joint with the same body on both sides;
  - no grounded body when there is at least one joint (`.nothingGrounded`).

  Bodies not connected to a grounded body through joints are not sent to OndselSolver; they keep their placements. Their joints are judged geometrically and marked `.notConnected`. Joints between two grounded bodies are judged without solving. Cost if wrong: none.

- **Ruling: `CADModel` resolves joint frames on the part's own topology, not on the moved instance.** It resolves the element with `InstanceResult.element(_:_:body:parameters:)`; indices are shared with the moved topology. It then calls `GeometryFrame.frame` on the part's `BodyResult.topology`. The brief pointed at `InstanceResult.frame(face:edge:body:parameters:)`, which works in assembly coordinates. There, the x axis chosen by "first global axis not close to z" would depend on the placement guess, and so would a fixed joint's result. Part coordinates make the markers independent of the guess. Cost if wrong: none; the frame helper is shared.
- **Ruling: joints mate faces.** Side b's frame is turned 180° about its x axis, so two faces' outward normals end up pointing at each other: a lid's bottom face on a box's top face lies flush. `flip: true` on the joint keeps b's frame unturned. For cylindrical faces, flip reverses which way the part points along the shared axis. Cost if wrong: agents must learn one flag; the prompt teaches it.
- **Ruling: a frame reference is `{ instance (id), body?, face, edge?, offset? }`.** `offset` is `{ x, y, z, angle }` (Scalars, millimetres and degrees, default 0). It moves the frame by (x, y, z) along its own axes, then turns it by `angle` about its own z. It is applied before the mate turn. Cost if wrong: an agent needing a rotated offset about x or y uses a second face.
- **Ruling: a joint is `{ id, name, kind, a, b, flip, limits? }`.** `limits` is `{ min?, max? }` (Scalars). It is stored and round-tripped, but PR 11 uses it; the listing does not show it and the tools do not accept it yet. Joint names are identifiers unique among joints (default `<Kind><n>`, for example `Revolute1`). Joint ids join the duplicate-id check. Cost if wrong: none.
- **Ruling: the document placements are the solver's initial guess; solved placements are results and are never written back.** Rebuilding the same document gives the same result, and undo and diffs stay meaningful. The instance keeps its `placement`, `InstanceResult.transform` is the solved placement, and the listing shows both when they differ (`at origin → solved (0, 0, 30)`). Cost if wrong: a solve that depends on the guess can differ from what an agent expects; the retry makes typical mates guess-independent.
- **Ruling: rebuild statuses.** `JointStatus`:
  - `ok`;
  - `redundant`;
  - `failed(String)`, for example "conflicts with other joints", "not satisfied: origins 4.2 mm apart, axes 90° apart", "Box1.top matches 0 faces …", "Lid did not build: …", "no instance is grounded; ground one with edit_instance", "Cap is not connected to a grounded instance", "no assembly solver is available", or "the solver failed: …".

  Instances with a failed frame or status are left out of the solve. Their joints fail, and so do joints to them. When the solve fails, instances keep their document placements. Cost if wrong: none.

- **Ruling: `RebuildEngine(kernel:sketchSolver:assemblySolver:)`, `CADSession(document:kernel:sketchSolver:assemblySolver:)`, `Grader` and `BenchRunner` take `(any AssemblySolving)? = nil`.** The app and `cadbench` pass `OndselAssemblySolver()`. Cost if wrong: a host that forgets the solver sees every joint fail loudly.
- **Ruling: `instanceSolids(of:)` runs the whole build and returns the solved instance bodies.** Grading needs the solved placements, and frames need the part topology. Cost if wrong: grading tessellates once more.
- **Ruling: tool edits keep references working.**
  - `delete_instance` also removes the joints that use the instance and reports "Removed joints: …".
  - `rename_feature` rewrites the face and edge references of joints on instances of that part.
  - Joint offsets and limits join the expression audit.
  - Instance body references in joints are not renumbered in this layer; a stale one fails with the part's body list.

  Cost if wrong: after a body renumbering, a multi-body joint reference needs a manual fix.

- **Ruling: bench checks.**
  - `jointsSatisfied { minimum?: Int = 1, kinds?: [kind] }` passes when the assembly has at least `minimum` joints, every joint is ok or redundant, and every listed kind appears.
  - `instancePosition { instance, relativeTo?, translation: [x, y, z], tolerance = 0.01 }` compares the solved translation of the instance's transform (its part origin in assembly coordinates), minus that of `relativeTo` when given.
  - The gate also fails on a failed joint.
  - `unchangedExcept` compares joints by name (kind, instance names, references, flip, offset) and gains `joints: [names]`.

  Cost if wrong: none.

## Review Focus

1. **Two joints that conflict** (a lid fixed flush on top and also fixed 5 mm higher). Expected: one or both fail "conflicts with other joints" or "not satisfied", nothing crashes, instances stay finite, and the listing shows it. Pinned in Task 2 (`conflictingFixedJoints`) and Task 4 (`conflictingJointsReported`).
2. **No grounded instance, or a jointed pair not connected to anything grounded.** Expected: a clear failure naming the fix; nothing moves arbitrarily. Pinned in Task 2 (`nothingGrounded`, `islandKeepsPlacement`) and Task 4 (`noGroundedInstance`).
3. **A joint whose face reference breaks** (the part's feature is renamed by hand or deleted, or the face is spherical). Expected: that joint fails naming the reference; the other joints still solve. Pinned in Task 4 (`brokenReferenceFailsOnlyThatJoint`).
4. **A start far from the solution, or flipped.** For example, the lid starts upside down 100 mm away, or the part starts rotated 90°. Expected: the retry lands the mate exactly. Pinned in Task 2 (`flippedStartRetries`, `singularStartRetries`).
5. **Concurrent rebuilds** (the app and a tool rebuilding at once). Expected: solves are serialised, results are identical, and the strict pool never hangs. Pinned in Task 2 (`concurrentSolves`).

## File Structure

`Packages/CADSolvers/`:

- `Package.swift`: targets `OndselSolver` and `COndselSolver`; `CADSolvers` depends on both C targets.
- `Scripts/vendor-ondselsolver.sh` (new).
- `Sources/OndselSolver/{VENDORED.md, LICENSES/OndselSolver-LGPL-2.1.txt, NarrowingWrappers.cpp, include/module.modulemap, include/OndselSolver/*}`.
- `Sources/COndselSolver/{include/COndselSolver.h, COndselSolver.cpp}`.
- `Sources/CADSolvers/`:
  - `Assembly.swift` (`RigidPlacement`, `AssemblyBody`, `AssemblyJointKind`, `AssemblyJoint`, `AssemblySystem`);
  - `AssemblyValidation.swift`;
  - `AssemblySolver.swift` (connectivity, attempts, retry);
  - `AssemblySolution.swift` (`JointState`, `AssemblySolution`, `AssemblySolverError`);
  - `JointCheck.swift` (the geometric judgement);
  - `OndselSystem.swift` (the handle wrapper).
- Tests: `AssemblyValidationTests.swift`, `AssemblySolveTests.swift`, `AssemblyDiagnosisTests.swift` and `AssemblyFixtures.swift`.

`Packages/CADModel/Sources/CADModel/`:

- `Joint.swift` (new): `Joint`, `JointKind`, `JointFrameRef`, `JointOffset`, `JointLimits`.
- `AssemblySolving.swift` (new): the protocol and the `SolverAssembly*` types.
- `JointResolver.swift` (new): frames from references.
- `AssemblySolve.swift` (new): runs the solve inside a rebuild.
- Modified: `Assembly.swift`, `CADDocument.swift`, `AssemblyResult.swift`, `AssemblyBuilder.swift`, `RebuildEngine.swift`, `RebuildEngine+Solids.swift`.
- `Sources/CADModelSolvers/OndselAssemblySolver.swift` (new).
- Tests:
  - `CADModelTests/{JointCodingTests,JointRebuildTests,FakeAssemblySolver}.swift`;
  - `CADModelSolversTests/AssemblyIntegrationTests.swift`.

`Packages/CADAssistantTools/`:

- `JointTools.swift` (new): `AddJointTool`, `EditJointTool`, `DeleteJointTool`.
- `JointArguments.swift` (new).
- Modified: `AssemblyListing.swift`, `WriteReport.swift`, `InstanceTools.swift` (delete removes joints), `FeatureLifecycleTools.swift` (rename rewrites joints), `ExpressionAudit.swift`, `Arguments.swift`, `CADSession.swift`, `CADTools.swift`, `CADAssistantPrompt.swift`, `ToolSchemas.swift`.
- CADBench: `Check.swift`, `Grader.swift`, `DocumentComparison.swift`, `BenchRunner.swift`; `CADBenchCLI/CADBenchCommand.swift`.
- Tests: `JointToolTests.swift` (new), `DocumentListingTests.swift`, `WriteReportTests.swift`, `CheckDecodingTests.swift`, `GraderTests.swift`, `TaskGradingTests.swift`, and a fake assembly solver.

Bench: `Bench/tasks/{pin-in-hole,lid-on-box,slider-on-rail}/`, `Bench/README.md`.

App:

- `Document/CADModelDocument+Session.swift`.
- `Views/FeatureOutlineView.swift` (joint rows).
- `Views/JointInspectorView.swift` (new).
- `Views/ContentView.swift`.
- `Viewport/ViewportContent.swift` (a joint id selects the assembly).
- Tests: `3DModellerAppTests/AssemblyDisplayTests.swift`.

Docs: `CLAUDE.md`, `NOTICE`.

---

### Task 1: Vendor OndselSolver

**Files:** `Scripts/vendor-ondselsolver.sh`, `Sources/OndselSolver/**`, `Package.swift`.

- [ ] **Step 1:** Write the script. Pin `ONDSEL_URL=https://github.com/FreeCAD/OndselSolver.git` and `ONDSEL_COMMIT=4be80eef02a3486cda0d78f3ccbb308d207a9639`. The script clones into a temp dir and checks out the commit. It then parses the file names from `OndselSolver/CMakeLists.txt` (`set(ONDSELSOLVER_SRC …)` and `set(ONDSELSOLVER_HEADERS …)`), copies them plus every `OndselSolver/*.h` into `Sources/OndselSolver/include/OndselSolver/`, and copies `LICENSE` to `LICENSES/OndselSolver-LGPL-2.1.txt`.
- [ ] **Step 2:** Write `NarrowingWrappers.cpp`:

```cpp
// OndselSolver narrows size_t to int in these files; they are compiled here, not directly, to silence that one
// warning without modifying vendored code or using unsafe flags.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#include "OndselSolver/AbsConstraint.cpp"
#include "OndselSolver/AtPointConstraintIqcJqc.cpp"
#include "OndselSolver/DirectionCosineConstraintIqcJqc.cpp"
#include "OndselSolver/TranslationConstraintIqcJqc.cpp"
#include "OndselSolver/SymbolicParser.cpp"
#pragma clang diagnostic pop
```

- [ ] **Step 3:** `Package.swift`: add these targets.

```swift
.target(
    name: "OndselSolver",
    exclude: ["VENDORED.md", "LICENSES"] + ondselWrapped.map { "include/OndselSolver/\($0)" },
    publicHeadersPath: "include",
    cxxSettings: [.define("NDEBUG")]
),
.target(name: "COndselSolver", dependencies: ["OndselSolver"], cxxSettings: [.define("NDEBUG")]),
```

`ondselWrapped` lists the five files. `CADSolvers` depends on `["CPlaneGCS", "COndselSolver"]`.

- [ ] **Step 4:** Write `VENDORED.md`: source, commit and date; the file rule; the excluded files; the wrapper and why; `NDEBUG`; the licence; the update steps.
- [ ] **Step 5:** Run `xcrun swift build` in `Packages/CADSolvers` (scratch path in the scratchpad) and check that it has zero warnings from our targets.
- [ ] **Step 6:** Commit `chore(solvers): vendor FreeCAD OndselSolver`, then `build(solvers): compile OndselSolver warning-free`.

### Task 2: Assembly solver in CADSolvers

**Interfaces, Produces (C, `COndselSolver.h`):**

```c
typedef struct OSAssembly OSAssembly;
enum { OS_OK = 0, OS_ERR_ARGUMENT = -1, OS_ERR_EXCEPTION = -2 };
enum { OS_FIXED = 0, OS_REVOLUTE = 1, OS_SLIDER = 2, OS_CYLINDRICAL = 3, OS_BALL = 4, OS_PLANAR = 5 };
/// Row-major rotation (as FreeCAD passes rows) and translation.
typedef struct { double rotation[9]; double translation[3]; } OSPlacement;
typedef struct { int32_t constraints; int32_t redundant; } OSJointReport;

OSAssembly *_Nullable os_create(void);
void os_destroy(OSAssembly *_Nullable assembly);
int32_t os_add_body(OSAssembly *assembly, OSPlacement placement, int32_t grounded);          // body index or < 0
int32_t os_add_joint(OSAssembly *assembly, int32_t kind, int32_t bodyA, OSPlacement markerA,
                     int32_t bodyB, OSPlacement markerB);                                    // joint index or < 0
int32_t os_solve(OSAssembly *assembly);                                                      // OS_OK or < 0
int32_t os_body_placement(const OSAssembly *assembly, int32_t body, OSPlacement *placement);
int32_t os_joint_report(const OSAssembly *assembly, int32_t joint, OSJointReport *report);
const char *os_last_error(const OSAssembly *assembly);
```

**Swift, Produces:**

```swift
public struct RigidPlacement: Sendable, Hashable {
    public var rotation: simd_double3x3      // columns are the body's axes in world coordinates
    public var translation: SIMD3<Double>
    public static let identity: RigidPlacement
    public init(rotation: simd_double3x3 = matrix_identity_double3x3, translation: SIMD3<Double> = .zero)
    public func point(_ p: SIMD3<Double>) -> SIMD3<Double>
    public func composed(with local: RigidPlacement) -> RigidPlacement   // self ∘ local
    public var inverse: RigidPlacement { get }
}
public struct AssemblyBody: Sendable, Hashable {
    public var placement: RigidPlacement; public var grounded: Bool
    public init(placement: RigidPlacement, grounded: Bool = false)
}
public enum AssemblyJointKind: Sendable, Hashable, CaseIterable { case fixed, revolute, slider, cylindrical, ball, planar }
public struct AssemblyJoint: Sendable, Hashable {
    public var kind: AssemblyJointKind
    public var bodyA: Int; public var markerA: RigidPlacement   // marker in body A's coordinates
    public var bodyB: Int; public var markerB: RigidPlacement
    public init(_ kind: AssemblyJointKind, _ bodyA: Int, _ markerA: RigidPlacement, _ bodyB: Int, _ markerB: RigidPlacement)
}
public struct AssemblySystem: Sendable, Hashable {
    public var bodies: [AssemblyBody]; public var joints: [AssemblyJoint]
    public init(bodies: [AssemblyBody] = [], joints: [AssemblyJoint] = [])
}
public enum JointState: Sendable, Hashable {
    case satisfied, redundant, conflicting, notConnected
    case unsatisfied(distance: Double, angle: Double)
}
public struct AssemblySolution: Sendable, Hashable {
    public let placements: [RigidPlacement]
    public let joints: [JointState]
    /// The solver's message when every attempt threw.
    public let failure: String?
    public let attempts: Int
}
public enum AssemblySolverError: Error, Sendable, Hashable {
    case invalidBody(index: Int, reason: String)
    case invalidJoint(index: Int, reason: String)
    case nothingGrounded
    case solverFailure(String)
}
public struct AssemblySolver: Sendable {
    public init()
    public func solve(_ system: AssemblySystem) throws(AssemblySolverError) -> AssemblySolution
}
```

C++ core of `os_solve`, with every entry point wrapped by a `guarded` that catches `std::exception` and `...` into a fixed 256-byte error buffer. The `joints.push_back(joint)` / `mbdJoints` push-backs record each `ASMTJoint` in addition order, so the reports can reach it after the solve.

```cpp
std::lock_guard<std::mutex> lock(solveMutex());
MutedStdout muted;                                   // swaps std::cout.rdbuf to a null buffer, restores in dtor
auto assembly = CREATE<ASMTAssembly>::With();
assembly->setName("OndselAssembly");
for (i, body) : parts[i] = CREATE<ASMTPart>::With(); name "body<i>"; mass marker (1, 1, [1,1,1]);
                setPosition3D / setRotationMatrix(rows); assembly->addPart(part);
                if grounded: assembly marker "ground<i>" at the placement, part marker "FixingMarker" at identity,
                             ASMTFixedJoint "grounding<i>" between them;
for (j, joint): part A marker "joint<j>a", part B marker "joint<j>b"; ASMT<kind>Joint "joint<j>";
                setMarkerI("/OndselAssembly/body<a>/joint<j>a"); setMarkerJ(".../body<b>/joint<j>b"); addJoint;
assembly->runPreDrag();
// placements: part->position3D, part->rotationMatrix; reports: mbdSystem->jointsMotionsDo, match name suffix
// "#joint<j>" or "/joint<j>", count constraintsDo, redundant when constraintSpec() starts with "Redundant".
```

- [ ] **Step 1: failing tests.** `AssemblyFixtures.swift` provides `rotation(axis:degrees:)` and a `ground` body at identity.
  - `AssemblyValidationTests`:
    - NaN translation → `.invalidBody(0, …)`;
    - a non-orthonormal rotation, and a reflection (det −1) → `.invalidBody`;
    - joint body 5 of 2 → `.invalidJoint(0, …)`;
    - the same body twice → `.invalidJoint`;
    - a NaN marker → `.invalidJoint`;
    - two bodies and a joint with nothing grounded → `.nothingGrounded`;
    - no joints and nothing grounded → the placements are returned unchanged.
  - `AssemblySolveTests`. Base is grounded at identity, with a marker at (0, 0, 10), z up.
    - `revoluteAlignsOriginsAndAxes`: Pin starts at (5, 3, 2), marker at identity. It ends at (0, 0, 10) with z up, and the joint is `.satisfied`.
    - `fixedCoincides`: Lid starts at (40, −20, 70) rotated 30° about Z, and ends with its frame equal to the base marker within 1e-6.
    - `sliderKeepsPositionAlongAxis`: Carriage starts at (2, 1, 25). It ends with x = y = 0 (on the base marker's z line), z = 25 and no rotation.
    - `cylindricalAllowsTurn`: the start rotated 20° about Z keeps the 20°.
    - `ballJoinsPoints`: the origins coincide and the rotation is free.
    - `planarKeepsInPlaneOffset`: a start at (5, 3, 2) rotated 36.87° about Z ends at (5, 3, 10) with its rotation kept.
    - `chain`: Base → revolute → Arm → fixed → Tip; every joint is satisfied.
  - `AssemblyDiagnosisTests`:
    - `conflictingFixedJoints`: fixed to the markers at z 10 and z 20. At least one joint is `.conflicting` or `.unsatisfied`; none is `.satisfied` with the lid at z 10 and z 20 at once; the placements are finite.
    - `flippedStartRetries`: the Lid starts upside down (180° about X) at z 30 with a fixed joint. It ends exactly coincident, and `attempts == 2`.
    - `singularStartRetries`: rotated 90° about Y → satisfied, `attempts == 2`.
    - `redundantPairReported`: revolute plus cylindrical on the same frames, from the coincident start. No crash; each state is satisfied, redundant, conflicting or unsatisfied, and at least one is not `.satisfied`. The exact outcome is pinned when observed.
    - `islandKeepsPlacement`: two ungrounded bodies joined, plus a grounded one → their placement is unchanged and the joint is `.notConnected`.
    - `groundedPairJudged`: a joint between two grounded bodies whose frames coincide → `.satisfied`; offset by 3 → `.unsatisfied(distance: 3, …)`.
    - `concurrentSolves`: 8 revolute solves in a `TaskGroup` give equal results.
    - `timing`: a chain of 20 revolute links solves in under 5 s in a debug build; the time is recorded.
- [ ] **Step 2:** Run `xcrun swift test --package-path Packages/CADSolvers --filter Assembly` and expect it to fail to compile.
- [ ] **Step 3:** Implement the C shim, `OndselSystem.swift`, validation, `JointCheck`, and the solver with connectivity (union-find over joints from grounded bodies), the first attempt, the coincident-start retry and the choice between attempts.
- [ ] **Step 4:** Run the whole package, then again under `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 timeout 300`.
- [ ] **Step 5:** Commit `feat(solvers): wrap OndselSolver behind a C shim`, then `feat(solvers): solve assemblies through OndselSolver`.

### Task 3: Joints in the document

**Produces (`Joint.swift`):**

```swift
public enum JointKind: String, Codable, Sendable, Hashable, CaseIterable {
    case fixed, revolute, slider, cylindrical, ball, planar
}
public struct JointOffset: Codable, Sendable, Hashable {       // all default 0; encode only non-zero? no: all keys
    public var x: Scalar; public var y: Scalar; public var z: Scalar; public var angle: Scalar
    public init(x: Scalar = 0, y: Scalar = 0, z: Scalar = 0, angle: Scalar = 0)
}
public struct JointFrameRef: Codable, Sendable, Hashable {
    public var instance: UUID
    public var body: String?
    public var face: GeometryReference
    public var edge: GeometryReference?
    public var offset: JointOffset?
    public init(instance: UUID, body: String? = nil, face: GeometryReference, edge: GeometryReference? = nil,
                offset: JointOffset? = nil)
}
public struct JointLimits: Codable, Sendable, Hashable { public var min: Scalar?; public var max: Scalar? }
public struct Joint: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID; public var name: String; public var kind: JointKind
    public var a: JointFrameRef; public var b: JointFrameRef
    public var flip: Bool                 // decode default false
    public var limits: JointLimits?       // reserved for motion (PR 11)
    public init(id: UUID = UUID(), name: String, kind: JointKind, a: JointFrameRef, b: JointFrameRef,
                flip: Bool = false, limits: JointLimits? = nil)
}
// Assembly gains: public var joints: [Joint]  (init default [], decodeIfPresent)
extension CADDocument { public var joints: [Joint]; public func joint(named: String) -> Joint? }
```

- [ ] **Step 1: failing tests** (`JointCodingTests`):
  - `roundTrip`: a revolute with an edge, an offset with an expression, limits and flip → equal after a round trip.
  - `pr9DocumentsLoad`: `"assembly": {"instances": [...]}` → `joints == []`.
  - `defaults`: `{"name", "kind", "a": {"instance", "face": {"name": "Box1.top"}}, "b": …}` → flip false, no offset, no edge.
  - `unknownKind` throws.
  - `duplicateJointID` → `DocumentError.duplicateID`.
- [ ] **Step 2–4:** Run, implement (add joint ids to the id check in `CADDocument.init(from:)`), and run the CADModel suite.
- [ ] **Step 5:** Commit `feat(model): store assembly joints`.

### Task 4: Solving joints on rebuild

**Produces (`AssemblySolving.swift`):**

```swift
public struct SolverRigid: Sendable, Hashable { public var rotation: simd_double3x3; public var translation: SIMD3<Double> }
public struct SolverAssemblyJoint: Sendable, Hashable {
    public var kind: JointKind
    public var bodyA: Int; public var markerA: SolverRigid; public var bodyB: Int; public var markerB: SolverRigid
}
public struct SolverAssembly: Sendable, Hashable {
    public var bodies: [(placement: SolverRigid, grounded: Bool)]  // as a struct SolverAssemblyBody
    public var joints: [SolverAssemblyJoint]
}
public enum SolverJointState: Sendable, Hashable {
    case satisfied, redundant, conflicting, notConnected, unsatisfied(distance: Double, angle: Double)
}
public struct SolverAssemblySolution: Sendable, Hashable {
    public var placements: [SolverRigid]; public var joints: [SolverJointState]; public var failure: String?
}
public struct AssemblySolvingError: Error, Sendable, Equatable, CustomStringConvertible {
    public var body: Int?; public var joint: Int?; public var reason: String
}
public protocol AssemblySolving: Sendable {
    func solve(_ assembly: SolverAssembly) throws(AssemblySolvingError) -> SolverAssemblySolution
}
```

`SolverAssembly.bodies` uses a named struct `SolverAssemblyBody { placement, grounded }`, since tuples are not `Hashable`.

**Produces (`AssemblyResult.swift`):**

```swift
public enum JointStatus: Sendable, Equatable, CustomStringConvertible { case ok, redundant, failed(String) }
public struct JointResult: Sendable, Equatable, Identifiable { public let id: UUID; public let name: String; public let status: JointStatus }
// AssemblyResult gains: public let joints: [JointResult]; func joint(id:) / joint(named:)
// InstanceResult.transform is the solved placement; new: public let placed: RigidTransform? (document placement)
// RebuildResult.failedJointCount
```

Rebuild (`AssemblySolve.swift`, called from `RebuildEngine.build` after the instances are placed):

1. `JointResolver.frames(joint, instances, partResults, parameters)` resolves each side:
   - the element comes from `InstanceResult.element`;
   - `GeometryFrame.frame` runs on the part's unmoved topology;
   - the offset is applied (translate along the local axes, then rotate by `angle` about the local z);
   - side b gets the mate turn (unless `flip`).

   The result is the local marker. Errors become `JointStatus.failed`.

2. The bodies are the ok instances used by resolvable joints, plus the grounded ones; `placement` is the instance transform.
3. Without an `assemblySolver`, every joint fails "no assembly solver is available". Otherwise the engine calls `solve` and maps each state:
   - satisfied → `ok`;
   - redundant → `redundant`;
   - conflicting → "conflicts with other joints";
   - notConnected → "<names> not connected to a grounded instance";
   - unsatisfied → "not satisfied: origins d mm apart, axes a° apart".

   A thrown `.nothingGrounded` fails every joint with "no instance is grounded; ground one with edit_instance".

4. For each instance whose solved placement differs from its document placement (more than 1e-9), the engine redoes `kernel.transform` with the solved `ResolvedPlacement`, converted from the rotation via `simd_quatd` to an axis and angle. It then remeasures, moves the mesh and topology from the part's result, and replaces the geometry keys.

- [ ] **Step 1: failing tests** (`JointRebuildTests`, fake kernel plus `FakeAssemblySolver`, which returns what the test scripts and records its input):
  - `markersInPartCoordinates`: an instance moved by (0, 0, 20) with a joint on `Box.top`. Marker A equals the part-local top frame (origin (w/2, d/2, h), z up), not the moved one.
  - `mateTurnsSideB`: marker B's z is the negated outward normal; with `flip` it is the normal.
  - `offsetApplied`: offset z 2 and angle 90 → origin +2 along z, and x becomes the old y.
  - `solvedPlacementMovesInstance`: the scripted placement (0, 0, 30) → the instance bounds shift, `transform.translation.z == 30`, the geometry key measures at the new spot, and the document is untouched.
  - `noSolver`: the joint fails "no assembly solver is available" and the instances stay put.
  - `noGroundedInstance`.
  - `brokenReferenceFailsOnlyThatJoint`: two joints, one to `Box.nope` → it fails naming the reference, and the other is solved.
  - `failedInstanceFailsJoint`.
  - `conflictingJointsReported`: scripted `.conflicting` → "conflicts with other joints".
- [ ] **Step 2: failing integration tests** (`CADModelSolversTests/AssemblyIntegrationTests`, real kernel plus `OndselAssemblySolver`):
  - `lidOnBox`: a Box part (60×40×30) instance grounded and a Lid part (60×40×5) at the origin, with a fixed joint `Lid.bottom` → `Box.top` (via the part's face names). The lid's bounds are (0, 0, 30)…(60, 40, 35) within 1e-4.
  - `pinInHole`: a revolute on the circular edges → the pin axis is on the hole axis.
  - `sliderOnRail`.
  - `upsideDownLidStillMates`.
- [ ] **Step 3:** Implement: `OndselAssemblySolver` in `CADModelSolvers` (type mapping only), `JointResolver`, `AssemblySolve`, the `RebuildEngine` init and `instanceSolids` via the build.
- [ ] **Step 4:** Run both CADModel suites.
- [ ] **Step 5:** Commit `feat(model): resolve joint frames on part geometry`, `feat(model): solve joints on rebuild`, then `feat(model): adapt OndselSolver to assembly solving`.

### Task 5: Joint tools, listing and reports

Tools:

| Tool           | Arguments                                                                                          |
| -------------- | -------------------------------------------------------------------------------------------------- |
| `add_joint`    | `kind`, `a`, `b` (each `{instance, body?, face, edge?, offset?: {x,y,z,angle}}`), `name?`, `flip?` |
| `edit_joint`   | `joint`, `kind?`, `a?`, `b?` (replace the side), `flip?`, `new_name?`                              |
| `delete_joint` | `joint`                                                                                            |

Refusals:

- an unknown kind, listing the kinds;
- an unknown instance, listing the instances;
- the same instance on both sides;
- a duplicate or invalid name;
- a face or edge that does not resolve on the current result (checked like `add_instance` bodies, when the result is current, with `InstanceResult.element`);
- `edit_joint` with nothing to change.

The listing appends, after the instances:

```
  joints
    Hinge  revolute Base Box1.top + edge(...) ↔ Pin Pin1.bottom, flipped  ok
    Mate  fixed Box Box1.top ↔ Lid Lid1.bottom  failed: not satisfied: origins 4 mm apart
```

An instance line shows its solved placement when it differs from the document: `Lid  Lid at origin → solved (0, 0, 30)  ok`.

The write report gains:

- the focused joint's status (`WriteFocus.joint`);
- joint status changes in "Status changes elsewhere";
- `Joints:` for new or faulty joints;
- `Moved by joints: Lid (0, 0, 0) → (0, 0, 30)` for instances whose solved translation or rotation changed between the before and after results.

- [ ] **Step 1: failing tests** (`JointToolTests`, fake kernel plus the fake solver in the tools tests):
  - `addJointDefaults`: `Fixed1`, one undo step "Add joint Fixed1", and a report with "Fixed1: ok" and "Moved by joints: Lid".
  - `addJointRefusals`: each refusal above.
  - `editJointReplacesSide`.
  - `deleteJoint`.
  - `deleteInstanceRemovesJoints`: "Removed joints: Fixed1".
  - `renameFeatureRewritesJoints`: renaming `Box1` to `Shell` changes a joint face `Box1.top` → `Shell.top` on instances of that part only.
  - `offsetExpressionAudited`: `z: "missing + 1"` is refused.
  - `DocumentListingTests`: the joints section and the solved suffix.
  - `WriteReportTests`: a joint status change.
  - `RealKernelTests`: lid on box through the tools with the real solver.
- [ ] **Steps 2–4:** Run, implement (also the `assemblySolver:` parameter through `CADSession`, `BenchRunner`, `Grader` and the CLI; `CADTools.all`; the prompt), then run the tools suite.
- [ ] **Step 5:** Commit:
  - `feat(tools): list joints with their status`;
  - `feat(tools): report joints after writes`;
  - `feat(tools): add, edit and delete joints`;
  - `fix(tools): keep joints valid across instance and feature edits`;
  - `docs(tools): teach the assistant mating`.

The prompt section "## Joints (mating)" explains:

- frames: face normal or cylinder axis as z, origin at the centroid or the edge centre;
- mating turns b so that faces meet flush, and `flip` reverses that;
- what each kind leaves free;
- ground one instance first;
- the instance placement is only a starting guess; the solved position is shown after `→ solved`;
- recipes:
  - lid on a box: fixed `Lid.bottom` to `Box.top`, or planar to let it slide;
  - pin or bolt in a hole: revolute or cylindrical between the circular edge of the hole's top and the circular edge under the bolt head (concentric and flush), or cylindrical plus planar;
  - slider on a rail: slider on faces whose normals run along the rail;
  - offsets for gaps.

### Task 6: Bench

- [ ] **Step 1: failing tests:**
  - decoding `jointsSatisfied` and `instancePosition`, with unknown keys refused;
  - `GraderTests` (fake solver): `jointsSatisfied` fails with no joints, with a failed joint and with a missing kind; `instancePosition` compares relative translation; the gate fails on a failed joint;
  - `DocumentComparisonTests`: a joint change outside `joints` is reported.
- [ ] **Step 2:** Implement the checks, the gate, and `unchangedExcept.joints`.
- [ ] **Step 3:** Write the tasks, with references built through the tools' vocabulary:
  - **`pin-in-hole`** (build).
    - Parts:
      - `Plate`: a 40×40×10 box at the origin with a ⌀11 hole through (20, 20) (cylinder r 5.5 subtracted);
      - `Pin`: a cylinder r 5, h 30 at the origin.
    - Assembly: `Base` (Plate) is grounded. `Pin` has a revolute joint between the plate's bottom circular hole edge and the pin's bottom circular edge, flipped so the pin points up with its bottom flush with the plate bottom.
    - Checks:
      - gate;
      - jointsSatisfied kinds [revolute];
      - instancePosition Pin relative to Base (20, 20, 0);
      - instanceBounds Pin (15, 15, 0)…(25, 25, 30);
      - noInterference;
      - referenceIoU 0.999.
    - Wrong solutions: `pinPlacedWithoutJoint` (the same placement, no joint → "joints"); `pinThroughTop` (the joint on the top edge → "position").
  - **`lid-on-box`** (build).
    - Parts: `Box` 60×40×30 and `Lid` 60×40×5, both at the origin.
    - Assembly: `Box` is grounded; `Lid` has a fixed joint `Lid.bottom` → `Box.top`.
    - Checks:
      - gate;
      - jointsSatisfied;
      - instanceBounds Lid (0, 0, 30)…(60, 40, 35);
      - noInterference;
      - referenceIoU 0.999.
    - Wrong solutions: `lidFloating` (placed at z 31 without a joint → "joints"); `lidInside` (the joint without the mate turn, via flip → "no interference" or bounds).
  - **`slider-on-rail`** (build).
    - Parts: `Rail` 200×20×10 and `Carriage` 30×20×15, both at the origin.
    - Assembly: `Rail` is grounded. The `Carriage` rides on the rail's top face with a slider along X, starting 50 mm from the rail's end. The slider is between the rail end face (normal −X) with offset (0, 0, 0), and the carriage end face, offset so the carriage sits on top. The reference is tuned in the test.
    - Checks:
      - gate;
      - jointsSatisfied kinds [slider];
      - instanceBounds Carriage min (50, 0, 10) max (80, 20, 25);
      - noInterference;
      - referenceIoU 0.999.
    - Wrong solution: `carriageRotated` (a cylindrical joint whose start is rotated 90° → "joints").

  Add the ids and wrong solutions to `TaskGradingTests` (real kernel plus both solvers), update the `Bench/README.md` tables, and pass the solver in `TaskGradingTests`.

- [ ] **Step 4:** Commit `feat(bench): grade joints`, then `feat(bench): add joint assembly tasks`.

### Task 7: App

- [ ] **Step 1: failing app tests** (`AssemblyDisplayTests`):
  - `ViewportContent.following` returns `.assembly` for a joint id;
  - a real rebuild of the lid-on-box document through `CADModelDocument`'s session shows the lid's display bounds at z 30…35 (solved, not at the document placement).
- [ ] **Step 2:** Implement:
  - the session with `OndselAssemblySolver()`;
  - an outline "Joints" group inside the Assembly section, with rows showing a symbol per kind (`lock`, `arrow.triangle.2.circlepath`, `arrow.left.and.right`, `cylinder`, `circle.circle`, `square.stack`), the name, "A ↔ B" and a status icon;
  - `JointInspectorView` (read-only: kind, sides, flip, status);
  - `ContentView` selection wiring.

  Regenerate with `xcodegen` only if needed. Run the app tests with derived data in the scratchpad.

- [ ] **Step 3:** Commit `feat(app): solve joints in the app session`, then `feat(app): list joints in the outline`.

### Task 8: Docs, checks, final review

- [ ] `CLAUDE.md`: joints and OndselSolver. `NOTICE`: OndselSolver (LGPL-2.1, pinned commit, source location). CI already runs `Test CADSolvers`. Commits `docs: describe the assembly solver`, then `docs(notice): credit OndselSolver`.
- [ ] Run a clean `xcrun swift test --package-path <pkg> --scratch-path <scratchpad>/clean` for CADSolvers, CADModel and CADAssistantTools; the 150 ms long-expression check; and a strict-pool run with `timeout 300`.
- [ ] Run a fresh `opus` reviewer over `git merge-base cad/09-assemblies HEAD..HEAD`, then one fix pass. Record the execution rulings and deferred items here.

## Self-review

- **Spec coverage.**
  - OndselSolver vendored behind a shim: Tasks 1–2.
  - Joints of six kinds between frame references: Tasks 3–4.
  - Per-joint failures on conflict or non-convergence: Tasks 2 and 4.
  - `add_joint` and `edit_joint` (plus `delete_joint`), with joint states in write results: Task 5.
  - The listing: Task 5.
  - The bench "joints satisfied" check: Task 6.
  - The app: Task 7.
  - DOF, limits, `move_joint`, drag and animate: deferred to PR 11 by the spec's PR table; `limits` is stored.
- **Types.** These names are consistent across Tasks 2–7:
  - `AssemblySolver`, `AssemblySystem`, `AssemblyBody`, `AssemblyJoint`, `AssemblyJointKind`, `RigidPlacement`, `JointState`, `AssemblySolution`, `AssemblySolverError`;
  - `Joint`, `JointKind`, `JointFrameRef`, `JointOffset`, `JointLimits`;
  - `AssemblySolving`, `SolverAssembly`, `SolverAssemblyBody`, `SolverAssemblyJoint`, `SolverRigid`, `SolverJointState`, `SolverAssemblySolution`, `AssemblySolvingError`;
  - `JointStatus`, `JointResult`, `OndselAssemblySolver`.
