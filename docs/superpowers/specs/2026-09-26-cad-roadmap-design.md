# Parametric CAD roadmap: design

Date: 2026-09-26. Status: approved in conversation; delivered as a stack of PRs.
Builds on: `docs/superpowers/specs/2026-09-26-geometry-kernel.md` and the spike findings in `docs/spikes/2026-09-26-occt-kernel.md` (PR #10).

## Goal

You describe a part or an assembly in words, and an agent models it: sketches, features, bodies, parts, joints. Agents can also change existing models reliably. Success is measured by a benchmark of build and modify tasks that agents run without a UI, not by the UI.

## Decisions

| Topic               | Decision                                                                                                                                                  |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Old model           | Drop it with no backward compatibility: `SceneManager`, RealityKit primitives, the `.scene3d` format and `CreatePrimitiveTool` and its siblings all go.   |
| How the agent edits | It reads a compact text listing of the document and writes through typed tools. It never writes free-form code.                                           |
| Document scope      | Several parts, each with its own feature tree and possibly several bodies, plus one assembly, all in one file.                                            |
| Assemblies          | A full mate solver: fixed, revolute, slider, cylindrical, ball and planar joints, with degrees of freedom, limits and motion.                             |
| Constraint solvers  | Vendor FreeCAD's PlaneGCS (sketches) and OndselSolver (assemblies), both C++ and LGPL-2.1, pinned to a FreeCAD commit, behind thin C/Objective-C++ shims. |
| Units               | Millimetres in the model and the tools. The viewport scales to RealityKit metres.                                                                         |
| Benchmark           | `cadbench`, run on demand by the implementing agent, with results in each PR description. No CI job.                                                      |

## Global constraints

- macOS 26, Apple Silicon only (`ARCHS: arm64`), Swift 6 strict concurrency. Use `xcrun swift`, never bare `swift`.
- Only `CADKernel` imports OCCTSwift. Only `CADSolvers` contains C++ solver code. Every other target is pure Swift.
- No C++ exception may cross into Swift. Every kernel and solver call returns a typed error.
- The agent-facing surface (document, rebuild, tools) runs without the app or any UI.
- Every PR in the stack builds, passes its tests and leaves `main` shippable on its own.

## Architecture

```
App (SwiftUI, RealityKit)          views, document type, menus; thin
  └─ CADAssistantTools             AssistantTool implementations over CADModel (headless)
       └─ CADModel                 document, parameters, feature trees, sketches, assembly,
            │                      rebuild engine, naming, listing (pure Swift)
            ├─ CADKernel           OCCTSwift: solids, features, tessellation, metrics, export,
            │                      face/edge provenance
            └─ CADSolvers          PlaneGCS + OndselSolver behind a Swift API
cadbench (CLI)                     runs the assistant loop headlessly over CADAssistantTools
```

- `CADModel` talks to geometry through protocols (`GeometryKernel`, `SketchSolving`, `AssemblySolving`). Its unit tests use fakes; integration tests use the real packages.
- `SwiftUIAssistant` keeps its role. `CADAssistantTools` supplies the tools and the context (the listing).

## Document

- **File:** `.cadmodel`, a single JSON file with sorted keys and pretty-printing. Top level: `{ "format": 1, "units": "mm", "parameters", "parts", "assembly" }`. It stores no cached geometry; everything is rebuilt on open. Exported UTType: `com.example.3dmodeller.cadmodel`.
- **Parameters:** `[{ name, expression }]`. An expression is a number or basic arithmetic (`+ - * /`, parentheses) over other parameters. Evaluation is ordered, cycles are an error, and every numeric field in a feature or constraint accepts an expression.
- **Part:** `{ id, name, features: [Feature] }`.
- **Feature:** `{ id: UUID, name, suppressed, kind }`. `name` is unique within the part and is what agents use. References point to `id`, so renaming a feature is safe. `kind` is a typed enum:
  - Solids: `box`, `cylinder`, `sphere`, `cone` and `torus`, each with a placement.
  - `boolean(union|subtract|intersect, target body, tool bodies)` and `transform(body, placement)`.
  - Dress-up: `fillet(edge refs, radius)`, `chamfer(edge refs, distance)` and `shell(body, face refs, thickness)`.
  - Sketch-based: `sketch(plane, entities, constraints)`, `extrude(sketch, loops, extent, operation)` and `revolve(sketch, loops, axis, angle, operation)`.
  - Every solid-producing feature has an `operation`: create a new body, or join, cut or intersect into a named existing body. Bodies are named `Body1`, `Body2`, …
- **Assembly:** `{ instances: [{ id, name, part, body?, placement }], joints: [Joint] }`. A joint is `{ id, name, kind, a: frame ref, b: frame ref, limits? }`. A frame ref combines a named face with an optional edge or axis on a given instance.

## Rebuild

- Features replay in order, and each gets a status: `ok`, `failed(error)` or `skipped(dependsOn)`. A failure never aborts the rebuild, and later independent features still build.
- Rebuild runs off the main actor and returns an immutable result: bodies, meshes, statuses, sketch solve states, assembly placements and joint states. The UI and tools read that result.
- The document is a value type. Each edit registers its previous value with the window's `UndoManager`, so the menu, ⌘Z and agent edits share one history.

## Naming geometry

- For every operation, `CADKernel` reports which input produced which output face (the "generated" and "modified" history of the OCCT operations), keyed by the feature and the sketch entity or face role that created it. Examples: `Box1.top`, `Extrude1.side[Sketch1.line3]`, `Extrude1.end`, `Fillet1.face[0]`.
- Edges are named by their two adjacent faces: `edge(Box1.top, Box1.front)`.
- Filter references, CadQuery-style: `edges parallel Z`, `faces normal +Z`, `farthest +X`, `circular r=2.75`, combinable with `and`.
- References are stored as names or filters and resolved on every rebuild. A reference that matches nothing, or more than it should, makes the feature fail with an error that lists the candidates. The engine never picks one silently.

## Agent tools (`CADAssistantTools`)

- **Read:**
  - `get_listing`: the full document as text.
  - `find_geometry(target, filter)`: matching faces and edges with name, type, centre, normal or axis, and length or radius.
  - `measure`: distance, angle, bounding box, volume, area, interference.
  - `render_views`: top, front, right and iso PNGs, returned as images.
- **Write:**
  - Parameters and features: `set_parameter`, `add_feature`, `edit_feature`, `delete_feature`, `rename_feature`, `suppress_feature`.
  - Sketches: `add_sketch`, which takes all entities and constraints in one call, and `edit_sketch`.
  - Parts and assemblies: `add_part`, `add_instance`, `add_joint`, `edit_joint`, `move_joint`.
  - Output: `export`.
- **Every write returns** the affected statuses, body validity (closed, single solid), bounding boxes and volumes, sketch solve states, joint states, and the listing lines that changed.
- **The listing** is part of the assistant context on every turn:
  ```
  parameters: width = 60, depth = 40, t = 10, hole_d = 5.5
  part Plate
    Box1     box width×depth×t at origin       → Body1  ok
    Sketch1  on Box1.top: 4 circles ⌀hole_d, fully constrained  ok
    Cut1     extrude Sketch1 through all, cut Body1  → Body1  ok
    Fillet1  edges parallel Z of Body1, r=3            failed: radius too large for edge
  ```

## Sketches

- **Plane:** `XY`, `XZ`, `YZ`, or a named planar face, each with an optional offset.
- **Entities:** point, line, arc, circle and construction line.
- **Constraints:** coincident, horizontal, vertical, parallel, perpendicular, tangent, equal, distance, angle, radius, fixed.
- PlaneGCS solves the sketch on every rebuild. The result is fully constrained, under-constrained (with the remaining degrees of freedom), or over-constrained (with the conflicting constraints).
- Closed loops become profiles for `extrude` and `revolve`.

## Assemblies and motion

- OndselSolver solves the joints on every rebuild. Non-convergence or conflicting joints produce per-joint failures.
- Each joint reports its remaining degrees of freedom and its limits.
- `move_joint(name, value)` drives the solver. The viewport can drag an instance along its free axes and animate a joint through its range.
- Interference between instances is a measurement, computed by the kernel as the intersection of their bodies.

## Export

- STEP AP242 with assembly structure, names and colours (OCCT's document-based STEP export).
- STL and 3MF per body or instance.
- Available through File ▸ Export and the `export` tool.

## Benchmark (`cadbench`)

- **Tasks** live in `Bench/tasks/<id>/` and come in two kinds:
  - **Build:** a prompt plus checks.
  - **Modify:** a seed `.cadmodel`, a prompt and checks, plus an "unchanged elsewhere" check.
- **Checks, in order:**
  1. **Gate:** every feature rebuilds and every body is a valid closed solid.
  2. **Per-task assertions:** bounding box, volume, counts (bodies, faces, holes, instances), a parameter's value, joints satisfied, no interference.
  3. **Optional reference model:** volume overlap with it (intersection ÷ union) at or above a threshold.
- **Running:** `cadbench run [--tasks …] [--repeat k] [--model …]` reads `ANTHROPIC_API_KEY`. Output goes to `Bench/results/<timestamp>/`: per-task pass/fail, pass@k, tool calls, tokens, cost, and final documents and renders. Results aren't committed; summaries go into PR descriptions.
- **Growth:** every layer adds tasks for what it enables.

## PR stack

| #   | Branch                    | Contents                                                                                                                                                                                           |
| --- | ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `cad/01-kernel-hardening` | This spec; kernel off the main actor; typed per-call errors; real triangle counts                                                                                                                  |
| 2   | `cad/02-document-model`   | `CADModel`: document, parameters, parts, features (solids, boolean, transform), rebuild engine; `.cadmodel` document type; app switched over; `SceneManager`, `.scene3d` and the old tools removed |
| 3   | `cad/03-assistant-tools`  | `CADAssistantTools` (headless): listing, parameter and feature tools, undo; app wiring                                                                                                             |
| 4   | `cad/04-bench`            | `cadbench` CLI, task format, grader, first build and modify tasks                                                                                                                                  |
| 5   | `cad/05-naming`           | Face/edge provenance, references, `find_geometry`, fillet/chamfer/shell by reference                                                                                                               |
| 6   | `cad/06-feedback`         | Rich write results, `measure`, `render_views`                                                                                                                                                      |
| 7   | `cad/07-sketch-solver`    | PlaneGCS in `CADSolvers` (package only)                                                                                                                                                            |
| 8   | `cad/08-sketches`         | Sketch features, extrude/revolve, sketch tools, sketch display                                                                                                                                     |
| 9   | `cad/09-assemblies`       | Assembly model, instances, placements, assembly view and tools                                                                                                                                     |
| 10  | `cad/10-assembly-solver`  | OndselSolver in `CADSolvers`; joints                                                                                                                                                               |
| 11  | `cad/11-motion`           | DOF reporting, limits, `move_joint`, drag and animate                                                                                                                                              |
| 12  | `cad/12-export`           | STEP with assemblies, STL, 3MF                                                                                                                                                                     |

Each PR gets its own implementation plan in `docs/superpowers/plans/`, written when its predecessor is done, and bench numbers in its description from PR 4 on.

## Out of scope

Multiple configurations; drawings; sheet metal; import of external CAD beyond what `export` round-trips; collaboration; iOS/visionOS; Intel Macs.
