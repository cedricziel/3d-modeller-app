# CAD 07: Sketch Solver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new package `CADSolvers` solves 2D sketches with FreeCAD's PlaneGCS: entities and constraints in, solved coordinates and a solve state (fully constrained, under-constrained with DOF, over-constrained with the conflicting constraints, redundant, failed) out. Package only; the model and the tools use it from PR 8.

**Architecture:** Three targets in `Packages/CADSolvers`. `PlaneGCS` is FreeCAD's `planegcs` directory, unmodified, pinned to one FreeCAD commit, with a subset of Eigen 3.4.1 headers and small local shims for the FreeCAD base and Boost headers it includes. `CPlaneGCS` is a thin C++ shim with a pure C header: an opaque sketch handle, entity and constraint builders, `solve`, diagnosis getters; every entry point catches all C++ exceptions. `CADSolvers` is the Swift API in our own terms (`Sketch`, `SketchEntity`, `SketchConstraint`, `SketchSolver`, `SketchSolution`), validates every input into typed errors before C++ sees it, and maps PlaneGCS tags back to constraint indices.

**Tech Stack:** Swift 6 (tools 6.1), Swift Testing, C++23 (`cxxLanguageStandard: .cxx2b`, PlaneGCS uses `std::unreachable` and `std::numbers`), FreeCAD PlaneGCS at `6387346419221615a3ae500b834665301f867095`, Eigen 3.4.1 (`d71c30c47858effcbd39967097a2d99ee48db464`).

**Spec:** `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md` (decision "Constraint solvers", section "Sketches", PR-stack row 7). Previous layer: `docs/superpowers/plans/2026-09-26-cad-06-feedback.md`.

## Global Constraints

- macOS 26, Apple Silicon only, Swift 6 strict concurrency. Use `xcrun swift`, never bare `swift`.
- Only `CADSolvers` contains C++ solver code. No C++ exception may reach Swift; every failure is a typed error.
- No `unsafeFlags` (they break consumption by other packages); only `cxxSettings` defines and header search paths.
- Tests use Swift Testing and never block a cooperative thread waiting on other work; they must finish under `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`.
- Semantic commits, one concern each, no "and" in the subject, no co-author lines. Comments only for a non-obvious why.
- No two targets in one package may differ only by case. Clean builds go to the scratchpad and are deleted afterwards.

## Rulings

- **Ruling: PlaneGCS is vendored unmodified; everything it needs from outside `planegcs/` is a local shim.** `Sketcher/SketcherGlobal.h` defines `SketcherExport` empty and includes the standard headers FreeCAD's precompiled header supplied (`<cassert>`, `<cmath>`, `<iterator>`, `<utility>`). `Base/Console.h` is a no-op logger, `Base/Tools.h` and `FCConfig.h` are empty, `boost/math/constants/constants.hpp` and `boost/graph/graph_concepts.hpp` are empty (included, unused), and `boost_graph_adjacency_list.hpp` plus `boost/graph/connected_components.hpp` implement the four Boost Graph calls PlaneGCS makes (`adjacency_list`, `add_vertex`, `add_edge`, `num_vertices`, `connected_components`) with a vector adjacency list and an iterative DFS. Cost if wrong: an update of the pinned commit that uses more Boost needs the shim extended; the build fails loudly.
- **Ruling: only the Eigen headers PlaneGCS transitively includes on arm64 are vendored** (≈260 files, ≈4 MB), found by `clang++ -MM` over the PlaneGCS sources and the shim. `Scripts/vendor-planegcs.sh` reproduces the whole vendored tree from the two pinned commits. `EIGEN_MPL2_ONLY` is defined so no LGPL-only Eigen code can compile in. The few Eigen files under BSD (Intel MKL glue) and Apache-2.0 (`BFloat16.h`) keep their headers, and `COPYING.MPL2`, `COPYING.BSD`, `COPYING.APACHE` and `COPYING.README` ship next to them. Cost if wrong: a later Eigen include not in the subset fails the build; rerun the script.
- **Ruling: PlaneGCS builds with `NDEBUG` and `EIGEN_NO_DEBUG`, as FreeCAD's release builds do,** and with `_LIBCPP_DISABLE_DEPRECATION_WARNINGS` (Eigen 3.4 uses `std::float_denorm_style`, deprecated in C++23). An `assert` or `eigen_assert` would abort the process, which no exception handler can catch; the Swift layer rejects every input that could reach one. Cost if wrong: an internal inconsistency yields NaNs instead of an abort; the Swift layer reports non-finite results as `failed`.
- **Ruling: two C++ targets.** `PlaneGCS` exposes its headers (`include/`: Eigen subset, shims, `Sketcher/App/planegcs`) to dependents through a custom `module.modulemap` that `requires cplusplus` and exports no headers, so Swift never tries to import them. `CPlaneGCS` owns the C header Swift imports. Cost if wrong: none; merging them later is mechanical.
- **Ruling: angles are radians and lengths are unitless in `CADSolvers`,** like `CADKernel`; `CADModel` converts degrees in PR 8. Cost if wrong: none.
- **Ruling: entities are points, lines, circles and arcs; arcs run counter-clockwise from `startAngle` to `endAngle`.** Every entity carries a `construction` flag that the solver ignores and the solution preserves. Point references are `.point(i)` (a point entity), `.start(i)` / `.end(i)` (line or arc), `.center(i)` (circle or arc). Cost if wrong: ellipses, B-splines and slots-as-primitives are additive.
- **Ruling: constraints and their PlaneGCS mapping.** `coincident(p, q)` → `P2PCoincident`; `horizontal(line)` / `vertical(line)`; `parallel` / `perpendicular` (two lines); `tangent(a, b)` edge tangency: line–circle/arc → `Tangent(Line, Circle, ccw)` with the side taken from the input geometry (as FreeCAD's `tangentSide`), circle/arc–circle/arc → `Tangent(Circle, Circle)` (internal or external from the input); `tangentAt(p, q)` endpoint tangency (FreeCAD's endpoint-to-endpoint mode): `P2PCoincident` plus `AngleViaPoint` at 0 or π, whichever the input is closer to; `equal(a, b)`: two lines → equal length, two circles/arcs → equal radius; `distance(p, q, d)` → `P2PDistance`; `pointLineDistance(p, line, d)` → `P2LDistance` on the input's side; `angle(l1, l2, a)` → `L2LAngle` (counter-clockwise from `l1`'s direction to `l2`'s); `radius` / `diameter` (circle or arc); `fixed(p)` → `CoordinateX` and `CoordinateY` at the point's input position (so it takes part in diagnosis, unlike FreeCAD's parameter-level block); `pointOnLine(p, line)` (the infinite line); `pointOnCircle(p, curve)` (the full circle of a circle or arc). Cost if wrong: new constraint kinds are additive.
- **Ruling: every constraint `i` carries PlaneGCS tag `i + 1`; arc rules carry tag 0 and are never reported.** Conflicting and redundant tags map back to sorted, unique constraint indices. Cost if wrong: none.
- **Ruling: the solve runs DogLeg, then Levenberg–Marquardt, then BFGS, each from the input geometry** (FreeCAD's order without its SQP last resort); which results count is settled by the execution ruling on residuals below. On failure the input geometry is returned. Cost if wrong: a sketch only SQP could solve reports `failed`.
- **Ruling: diagnosis happens on the input geometry and, after a successful solve, again on the solved geometry; the reported state comes from the last diagnosis.** A solved sketch fed back as input therefore reports the same state, which PR 8 relies on when it stores solved geometry. Cost if wrong: one extra QR decomposition per successful solve.
- **Ruling: the state has one precedence:** conflicting constraints → `overConstrained(conflicting:)`; else not solved or non-finite output → `failed`; else redundant constraints → `redundant(_:)`; else DOF > 0 → `underConstrained(dof:)`; else `fullyConstrained`. `SketchSolution.degreesOfFreedom` always carries the last diagnosis's DOF. Cost if wrong: callers see one state where two apply; the DOF is still there.
- **Ruling: invalid input is refused with `SketchSolverError.invalidEntity(index:reason:)` or `.invalidConstraint(index:reason:)` before any C++ runs:** non-finite numbers, radius ≤ 0, a line shorter than 1e-9, an entity index out of range, the wrong entity kind for a constraint or a point role, the same entity or point twice, a distance, radius or diameter ≤ 0. A C++ exception or shim argument error becomes `.solverFailure(message)`. Cost if wrong: a degenerate but meaningful input (zero-length line as a sloppy guess) must be nudged by the caller.
- **Ruling: `SketchSolver.solve` is synchronous and `Sendable`;** each call builds its own PlaneGCS system, and PlaneGCS keeps no mutable global state (its logging singleton only forwards to the no-op console), so concurrent solves are safe. PlaneGCS's diagnosis runs one QR on a `std::async` thread and waits for it; that is an OS thread, not a Swift cooperative one, so it cannot starve the pool. Cost if wrong: callers would need a lock; a concurrent-solve test pins it.

- **Ruling (execution): a solve counts when the applied solution satisfies every constraint** (squared error of each tag, arc rules included, ≤ PlaneGCS's `convergence` 1e-10), for any PlaneGCS status except `Failed`. PlaneGCS checks redundant constraints against the parameters before it writes the solution back, so a sketch with a redundant constraint solved from a rough start came back `Converged` and would have read as `failed`. Cost if wrong: none found; a least-squares-only answer still fails the residual check.
- **Ruling (execution): conflicts name PlaneGCS's whole group.** A second width on the rectangle reports `[0, 1, 2, 3, 6, 7, 9, 11]` (both widths plus the coincidences and verticals linking them); a horizontal line between two fixed ends reports `[0, 1, 2]`; two different distances between a fixed and a free point report `[1, 2]`. Redundancy names the constraints PlaneGCS sets aside, not every one involved: an implied `parallel` on the rectangle reports `[11]`; the reviewer measured three identical distances reporting only one. Tests assert these exact sets. Cost if wrong: a vendor update that changes the grouping fails the tests loudly.
- **Ruling (execution): coincident plus edge `tangent` at one joint is not flagged; it converges only to about 2.5e-5** (the joint is a double root). `tangentAt` converges exactly. The planned claim that it shows as redundant was wrong and is dropped. Cost if wrong: PR 8 should steer agents to `tangentAt` for joints.
- **Ruling (execution): `-Wshorten-64-to-32`, which SwiftPM enables for C++ targets and PlaneGCS trips 28 times, is silenced by a pragma in the `SketcherGlobal.h` shim** (no unsafe flags). It also covers `CPlaneGCS.cpp`, which includes the PlaneGCS headers. Cost if wrong: a narrowing bug in the shim goes unwarned.
- **Measured (execution):** the 100-line staircase takes 1.3 s in a debug build and 0.06 s in release on an M-series Mac; 200 lines take 9.5 s debug and 0.35 s release. Unoptimised Eigen dominates; SwiftPM offers no safe way to optimise one target in debug.

- **Ruling (review): solved arcs come back normalised,** `startAngle` in [0, 2π) and `endAngle` in (`startAngle`, `startAngle` + 2π], since PlaneGCS leaves the angles unbounded and a reversed input stayed reversed. Cost if wrong: none; the arc is the same.
- **Ruling (review): the shim's error text lives in a fixed 256-byte buffer** and `ArgumentError` carries a `const char*`, so reporting an error cannot allocate and terminate inside a `noexcept` boundary. The residual check iterates the tags actually added. Cost if wrong: messages longer than 255 bytes are cut.
- **Ruling (review): the 100-entity timing budget is 20 s in debug builds, 1 s in release,** since CI runners are slower than the 1.3 s measured locally. Cost if wrong: a large debug slowdown goes unnoticed.

## Review Focus

1. A conflicting constraint pair (a horizontal line with a vertical constraint too, or two different distances on the same points). Expected: `overConstrained` with exactly those indices (not the arc rules, not unrelated constraints), input geometry returned. Pinned in Task 5 (`conflictingDistances`, `conflictingWidth`, `horizontalBetweenFixedEnds`).
2. Invalid indices, kinds and values. Expected: typed error naming the index; never a crash. Pinned in Task 3 (`invalidInputs`).
3. Tangency direction: a circle starting on one side of a line stays on that side. Pinned in Task 4 (`tangentKeepsSide`).
4. Solving from a sloppy guess converges to the dimensioned rectangle. Pinned in Task 4 (`sloppyRectangle`).
5. The 100-entity sketch and concurrent solves finish quickly under the strict cooperative pool. Pinned in Task 6.

## File Structure

`Packages/CADSolvers/`:

- `Package.swift` (new): products `CADSolvers`; targets `PlaneGCS`, `CPlaneGCS`, `CADSolvers`, test target `CADSolversTests`.
- `Scripts/vendor-planegcs.sh` (new): clones both pinned commits into a temp dir and rebuilds `Sources/PlaneGCS/include/Eigen` and `Sources/PlaneGCS/include/Sketcher/App/planegcs`.
- `Sources/PlaneGCS/VENDORED.md`, `Sources/PlaneGCS/LICENSES/` (FreeCAD `LICENSE` as `FreeCAD-LGPL-2.1.txt`, Eigen `COPYING.*`).
- `Sources/PlaneGCS/include/`: `module.modulemap`, `Eigen/…`, `Sketcher/App/planegcs/*` (vendored), `Sketcher/SketcherGlobal.h`, `Base/Console.h`, `Base/Tools.h`, `FCConfig.h`, `boost/…`, `boost_graph_adjacency_list.hpp` (shims).
- `Sources/CPlaneGCS/include/CPlaneGCS.h`, `Sources/CPlaneGCS/CPlaneGCS.cpp`.
- `Sources/CADSolvers/`: `Sketch.swift` (entities, references, constraints), `SketchValidation.swift`, `SketchSolver.swift`, `SketchSolution.swift`, `PlaneGCSSystem.swift` (the handle wrapper).
- `Tests/CADSolversTests/`: `ValidationTests.swift`, `SolveTests.swift`, `DiagnosisTests.swift`, `PerformanceTests.swift`.

Also: `.github/workflows/ci.yml` (step `Test CADSolvers`), `CLAUDE.md`, `NOTICE`.

---

### Task 1: Vendor PlaneGCS with shims

**Files:** `Packages/CADSolvers/Scripts/vendor-planegcs.sh`, `Packages/CADSolvers/Sources/PlaneGCS/{VENDORED.md,LICENSES/FreeCAD-LGPL-2.1.txt,include/Sketcher/**,include/Base/*,include/FCConfig.h,include/boost/**,include/boost_graph_adjacency_list.hpp,include/module.modulemap}`

- [ ] **Step 1:** Write the script (pinned SHAs as variables, `git clone --filter=blob:none --sparse` for FreeCAD, `git clone --depth 1 --branch 3.4.1` for Eigen, copy `src/Mod/Sketcher/App/planegcs/*` and `LICENSE`, then compute the Eigen subset with `xcrun clang++ -std=c++2b -MM` over `planegcs/*.cpp` and `CPlaneGCS.cpp` with the same defines as the package, normalise paths with `python3 -c os.path.normpath`, copy each file keeping its tree).
- [ ] **Step 2:** Write the shims (content as in the Rulings; `connected_components` returns the component count and fills the map by iterative DFS).

```cpp
// include/boost/graph/connected_components.hpp
template<typename O, typename V, typename D, typename ComponentMap>
int connected_components(const adjacency_list<O, V, D>& g, ComponentMap components)
{
    const std::size_t n = g.adjacency.size();
    std::vector<bool> seen(n, false);
    std::vector<std::size_t> stack;
    int count = 0;
    for (std::size_t start = 0; start < n; ++start) {
        if (seen[start]) continue;
        seen[start] = true;
        stack.push_back(start);
        while (!stack.empty()) {
            const std::size_t v = stack.back();
            stack.pop_back();
            components[v] = count;
            for (std::size_t w : g.adjacency[v]) {
                if (!seen[w]) { seen[w] = true; stack.push_back(w); }
            }
        }
        ++count;
    }
    return count;
}
```

- [ ] **Step 3:** `module.modulemap`: `module PlaneGCS { requires cplusplus }`. `VENDORED.md`: source URLs, commit SHAs and dates, file list rule, the shim list with reasons, the defines, licences, how to update.
- [ ] **Step 4:** Commit `chore(solvers): vendor FreeCAD PlaneGCS`.

### Task 2: Vendor the Eigen subset, package skeleton

**Files:** `Sources/PlaneGCS/include/Eigen/**`, `Sources/PlaneGCS/LICENSES/Eigen-*`, `Package.swift`, placeholder `Sources/CPlaneGCS/{include/CPlaneGCS.h,CPlaneGCS.cpp}`, `Sources/CADSolvers/SketchSolver.swift`, `Tests/CADSolversTests/ValidationTests.swift`.

```swift
// swift-tools-version: 6.1
import PackageDescription

let planeGCSSettings: [CXXSetting] = [
    .define("NDEBUG"),
    .define("EIGEN_NO_DEBUG"),
    .define("EIGEN_MPL2_ONLY"),
    .define("_LIBCPP_DISABLE_DEPRECATION_WARNINGS"),
]

let package = Package(
    name: "CADSolvers",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [.library(name: "CADSolvers", targets: ["CADSolvers"])],
    targets: [
        .target(
            name: "PlaneGCS",
            exclude: ["VENDORED.md", "LICENSES"],
            publicHeadersPath: "include",
            cxxSettings: planeGCSSettings
        ),
        .target(name: "CPlaneGCS", dependencies: ["PlaneGCS"], cxxSettings: planeGCSSettings),
        .target(name: "CADSolvers", dependencies: ["CPlaneGCS"]),
        .testTarget(name: "CADSolversTests", dependencies: ["CADSolvers"]),
    ],
    cxxLanguageStandard: .cxx2b
)
```

- [ ] **Step 1:** Run the script's Eigen part; copy licences.
- [ ] **Step 2:** Package skeleton, `xcrun swift build` succeeds with zero warnings from our targets.
- [ ] **Step 3:** Commit `chore(solvers): vendor the Eigen headers PlaneGCS needs`, then `build(solvers): add the CADSolvers package`.

### Task 3: Swift sketch model and validation

**Interfaces — Produces:**

```swift
public struct SketchPoint: Sendable, Hashable { public var x: Double; public var y: Double; public init(_ x: Double, _ y: Double) }
public enum SketchGeometry: Sendable, Hashable {
    case point(SketchPoint)
    case line(start: SketchPoint, end: SketchPoint)
    case circle(center: SketchPoint, radius: Double)
    case arc(center: SketchPoint, radius: Double, startAngle: Double, endAngle: Double)
}
public struct SketchEntity: Sendable, Hashable {
    public var geometry: SketchGeometry
    public var construction: Bool
    public init(_ geometry: SketchGeometry, construction: Bool = false)
    public static func point(_ x: Double, _ y: Double, construction: Bool = false) -> SketchEntity
    public static func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, construction: Bool = false) -> SketchEntity
    public static func circle(center: SketchPoint, radius: Double, construction: Bool = false) -> SketchEntity
    public static func arc(center: SketchPoint, radius: Double, from startAngle: Double, to endAngle: Double, construction: Bool = false) -> SketchEntity
}
public enum SketchPointRef: Sendable, Hashable { case point(Int), start(Int), end(Int), center(Int) }
public enum SketchConstraint: Sendable, Hashable {
    case coincident(SketchPointRef, SketchPointRef)
    case horizontal(Int), vertical(Int)
    case parallel(Int, Int), perpendicular(Int, Int)
    case tangent(Int, Int)
    case tangentAt(SketchPointRef, SketchPointRef)
    case equal(Int, Int)
    case distance(SketchPointRef, SketchPointRef, Double)
    case pointLineDistance(SketchPointRef, line: Int, Double)
    case angle(Int, Int, Double)
    case radius(Int, Double), diameter(Int, Double)
    case fixed(SketchPointRef)
    case pointOnLine(SketchPointRef, line: Int)
    case pointOnCircle(SketchPointRef, curve: Int)
}
public struct Sketch: Sendable, Hashable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]
    public init(entities: [SketchEntity] = [], constraints: [SketchConstraint] = [])
}
public enum SketchSolverError: Error, Sendable, Hashable {
    case invalidEntity(index: Int, reason: String)
    case invalidConstraint(index: Int, reason: String)
    case solverFailure(String)
}
extension Sketch { func validate() throws(SketchSolverError) }   // internal
```

- [ ] **Step 1: Failing tests** (`ValidationTests.swift`): a parameterised `invalidInputs` over (sketch, expected error): NaN coordinate, radius 0, zero-length line, constraint index 5 of 2 entities, `horizontal` on a circle, `.center` of a line, `.start` of a circle, `.point` of a line, `parallel(0, 0)`, `coincident(.start(0), .start(0))`, `distance` −1, `radius` 0, non-finite angle, `tangent` of two lines, `equal` of a line and a circle, `tangentAt` on a circle, `tangentAt` with a centre ref. Each expects the exact `SketchSolverError` case and index; the reason is checked to be non-empty.
- [ ] **Step 2:** Run, see them fail to compile.
- [ ] **Step 3:** Implement `Sketch.swift` and `SketchValidation.swift` (entity checks, then per-constraint `kind` checks through `entityKind(at:)`, `resolve(_ ref:)`).
- [ ] **Step 4:** Tests pass. Commit `feat(solvers): describe sketches with typed validation`.

### Task 4: C shim and solving

**Interfaces — Produces (C, `CPlaneGCS.h`):**

```c
typedef struct PGSSketch PGSSketch;
typedef struct { int32_t entity; int32_t role; } PGSPointRef;          // PGS_ROLE_POINT/START/END/CENTER
typedef struct { int32_t kind; int32_t first; int32_t second; PGSPointRef p1; PGSPointRef p2; double value; } PGSConstraint;
typedef struct { int32_t solved; int32_t dof; int32_t conflictingCount; int32_t redundantCount; } PGSReport;

PGSSketch *_Nullable pgs_create(void);
void pgs_destroy(PGSSketch *_Nullable sketch);
int32_t pgs_add_point(PGSSketch *sketch, double x, double y);                       // entity index, or < 0
int32_t pgs_add_line(PGSSketch *sketch, double x1, double y1, double x2, double y2);
int32_t pgs_add_circle(PGSSketch *sketch, double cx, double cy, double r);
int32_t pgs_add_arc(PGSSketch *sketch, double cx, double cy, double r, double start, double end);
int32_t pgs_add_constraint(PGSSketch *sketch, int32_t tag, PGSConstraint constraint); // PGS_OK or < 0
int32_t pgs_solve(PGSSketch *sketch, PGSReport *report);                           // PGS_OK or < 0
int32_t pgs_conflicting(const PGSSketch *sketch, int32_t *tags, int32_t capacity);  // count copied
int32_t pgs_redundant(const PGSSketch *sketch, int32_t *tags, int32_t capacity);
int32_t pgs_entity_values(const PGSSketch *sketch, int32_t entity, double *values, int32_t capacity);
const char *pgs_last_error(const PGSSketch *sketch);
```

`pgs_entity_values` writes point `x y`; line `x1 y1 x2 y2`; circle `cx cy r`; arc `cx cy r start end`.

**Swift — Produces:**

```swift
public enum SketchState: Sendable, Hashable {
    case fullyConstrained
    case underConstrained(dof: Int)
    case overConstrained(conflicting: [Int])
    case redundant([Int])
    case failed
}
public struct SketchSolution: Sendable, Hashable {
    public let entities: [SketchEntity]
    public let state: SketchState
    public let degreesOfFreedom: Int
}
public struct SketchSolver: Sendable {
    public init()
    public func solve(_ sketch: Sketch) throws(SketchSolverError) -> SketchSolution
}
```

The C++ side keeps every parameter in a `std::deque<double>` (stable addresses), entities in `std::deque<GCS::Point/Line/Circle/Arc>`, all unknowns in one `std::vector<double*>`, and wraps each entry point:

```cpp
template<typename F>
int32_t guarded(PGSSketch* sketch, F&& body) noexcept
{
    try {
        return body();
    }
    catch (const std::exception& error) {
        sketch->lastError = error.what();
    }
    catch (...) {
        sketch->lastError = "unknown C++ exception";
    }
    return PGS_ERR_EXCEPTION;
}
```

`pgs_solve`: `system.declareUnknowns(unknowns); system.initSolution(GCS::DogLeg);` then DogLeg / LM / BFGS until `Success`; on success `applySolution()`, `invalidatedDiagnosis()`, `initSolution()` (re-diagnose at the solution); else `undoSolution()`. Report `dofsNumber()`, `getConflicting`, `getRedundant` (tags > 0 only).

- [ ] **Step 1: Failing tests** (`SolveTests.swift`):
  - `rectangle`: four lines, four `coincident`, two `horizontal`, two `vertical`, `fixed(.start(0))`, `distance(.start(0), .end(0), 60)`, `distance(.start(1), .end(1), 40)` → `fullyConstrained`, DOF 0, corners at (0,0), (60,0), (60,40), (0,40) within 1e-9.
  - `sloppyRectangle`: same constraints, input corners off by up to 7 units and lines not quite axis-aligned → same result.
  - `underConstrained`: a lone point → `underConstrained(dof: 2)`; a free line → 4; the rectangle without its two distances → 2; the rectangle without its `fixed` → 2 (the two translations).
  - `tangentLineArc`: a fixed horizontal line on y = 0 (both ends `fixed`), an arc of radius 10 whose centre lies on a fixed vertical construction line at x = 5 (`pointOnLine`), `radius(1, 10)`, `tangent(0, 1)`, arc angles fixed by `fixed(.start)`… reduced to what the test asserts: the centre ends at (5, 10) because the input centre is above the line.
  - `tangentKeepsSide`: same with input centre below the line → centre y = −10.
  - `tangentAtJoint`: a line ending where an arc starts, `tangentAt(.end(0), .start(1))` plus a radius → the arc's centre sits one radius above the joint and its start angle is −π/2.
  - `circleRadiusDiameter`, `equalLines`, `angleBetweenLines` (60° = π/3), `perpendicularLines`, `parallelLines`, `pointOnCircle`, `pointLineDistance` spot checks.
  - `constructionFlagPreserved`.
- [ ] **Step 2:** Run, fail.
- [ ] **Step 3:** Implement `CPlaneGCS.h`, `CPlaneGCS.cpp`, `PlaneGCSSystem.swift` (a `~Copyable` struct or final class owning the handle, `deinit` destroys), `SketchSolver.swift`, `SketchSolution.swift`.
- [ ] **Step 4:** Pass. Commit `feat(solvers): wrap PlaneGCS behind a C shim`, then `feat(solvers): solve sketches through PlaneGCS`.

### Task 5: Diagnosis

- [ ] **Step 1: Failing tests** (`DiagnosisTests.swift`):
  - `conflictingDistances`: two points, `fixed(.point(0))`, `distance(.point(0), .point(1), 10)`, `distance(.point(0), .point(1), 20)`, → `overConstrained(conflicting:)` contains exactly the two distance indices; entities equal the input.
  - `conflictingWidth`: the rectangle plus a second width → the group PlaneGCS names.
  - `horizontalBetweenFixedEnds`: a sloped line with both ends fixed and `horizontal` → conflicting `[0, 1, 2]`.
  - `redundantParallel`: the rectangle plus `parallel(0, 2)` (implied by the two horizontals) from the sloppy start → `redundant([11])`, solved.
  - `coincidentWithEdgeTangentIsImprecise`: coincident plus edge tangent at a joint solves to within 1e-4.
  - `emptySketch` → `fullyConstrained`, DOF 0.
- [ ] **Step 2–4:** Implement the precedence in `SketchSolver`, pass, commit `feat(solvers): report conflicting constraints`.

### Task 6: Performance and concurrency

- [ ] **Step 1:** `PerformanceTests.swift`: `hundredEntities` builds a chain of 25 rectangles (100 lines) where each rectangle's first corner is coincident with the previous one's third, all dimensioned, the first corner fixed, from a sloppy guess; expects `fullyConstrained` and a wall time under 5 s in a debug build (recorded measured time in the ledger). `concurrentSolves` runs 8 rectangle solves in a `TaskGroup` and expects all equal.
- [ ] **Step 2:** Run normally and under `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 timeout 300 xcrun swift test`.
- [ ] **Step 3:** Commit `test(solvers): bound the solve time of a 100-entity sketch`.

### Task 7: CI, docs, notice

- [ ] **Step 1:** `.github/workflows/ci.yml`: step `Test CADSolvers` (`working-directory: Packages/CADSolvers`, `xcrun swift test`) before the app step. Commit `ci: test CADSolvers`.
- [ ] **Step 2:** `CLAUDE.md`: build command line and a **CADSolvers** paragraph. `NOTICE`: PlaneGCS (FreeCAD, LGPL-2.1-or-later, pinned commit) and Eigen (MPL-2.0, with the BSD/Apache files named). Commits `docs: describe CADSolvers`, `docs(notice): credit PlaneGCS and Eigen`.
- [ ] **Step 3:** Clean build `xcrun swift test --package-path Packages/CADSolvers --scratch-path <scratchpad>/clean`, then delete it.

### Task 8: Final review

- [ ] Fresh `opus` reviewer over `git merge-base cad/06-feedback HEAD..HEAD`; one fix pass for Critical/Important; ledger updated with execution rulings.

## Self-review

- Spec coverage: PlaneGCS pinned and vendored (Tasks 1–2), shim with no exceptions crossing (Task 4), Swift API with solve states (Tasks 3–5), tests the brief lists (Tasks 3–6), CI and notices (Task 7). App and model integration are PR 8.
- Types: `Sketch`, `SketchEntity`, `SketchGeometry`, `SketchPointRef`, `SketchConstraint`, `SketchSolver`, `SketchSolution`, `SketchState`, `SketchSolverError` keep these names through Tasks 3–6.

## Deferred after the final review

- `SketchState.failed` without conflicts is not covered by a test; no small sketch that PlaneGCS fails to solve without a conflict was found.
- `satisfiesEveryConstraint` costs O(tags × constraints) through `calculateConstraintErrorByTag`; 3000 constraints took 17 ms in release.
- Int→Int32 casts of entity indices and tags trap only above 2³¹ entries.
- Debug builds of the app (PR 8) will run PlaneGCS unoptimised (about 20× slower); consider solving only on change, or an optimised configuration for the package in the Xcode project.
