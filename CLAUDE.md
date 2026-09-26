# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation

Always use context7 when I need code generation, setup or configuration steps, or
library/API documentation. This means you should automatically use the Context7 MCP
tools to resolve library id and get library docs without me having to explicitly ask.

## Development Approach

This project follows **Test-Driven Development (TDD)**:

1. Write tests first that define expected behavior
2. Run tests to confirm they fail
3. Implement the minimum code to make tests pass
4. Refactor while keeping tests green

## Build Commands

```bash
# Generate/regenerate Xcode project (after modifying project.yml)
xcodegen generate

# Build via Xcode
open 3DModellerApp.xcodeproj
# Or from command line:
xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp build

# Run app tests
xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test

# Build via Swift Package Manager (alternative)
xcrun swift build

# Run package tests
cd Packages/SwiftUIAssistant && xcrun swift test
cd Packages/SwiftUIAssistantTools && xcrun swift test
cd Packages/CADKernel && xcrun swift test
cd Packages/CADModel && xcrun swift test
cd Packages/CADAssistantTools && xcrun swift test   # includes the CADBench tests
cd Packages/CADSolvers && xcrun swift test

# Benchmark (calls the Claude API; see Bench/README.md)
xcrun swift run --package-path Packages/CADAssistantTools cadbench run

# Run a single test
xcrun swift test --filter SwiftUIAssistantTests.AssistantTests/testSendMessage
```

Always use `xcrun swift`, not bare `swift`: the `swift` on `$PATH` may be a toolchain that doesn't match the Xcode SDK and fails or hangs.

## Architecture

This is an AI-first parametric CAD app for macOS. A document holds parameters, parts with feature trees, and an assembly of placed part instances; a rebuild engine replays the features through the Open CASCADE kernel. The chat assistant reads a text listing of the document and edits it through typed tools (see `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md`).

### Package Structure

**SwiftUIAssistant** (`Packages/SwiftUIAssistant/`) - Standalone, reusable library for adding AI assistant capabilities to any SwiftUI app:

- `LLMProvider` protocol - Abstraction for AI backends (Claude implemented; `ClaudeProvider` defaults to `claude-opus-5-5`, effort `medium`)
- `AssistantTool` protocol - Define executable tools the AI can invoke
- `Assistant` class - Orchestrates LLM calls and tool execution loops
- `AssistantContext` protocol - Host app provides scene state to AI. With `AssistantConfiguration.attachesContextToMessages` the context travels with each user message (`Message.context`) instead of the system prompt, which stays fixed per conversation
- `ToolParameter.custom` - a parameter with its own JSON Schema (unions, nested objects, arrays)
- SwiftUI views: `AssistantPanel`, `AssistantView`, `MessageBubbleView`, etc.

**SwiftUIAssistantTools** (`Packages/SwiftUIAssistantTools/`) - Common `AssistantTool`s: `FetchTool`, `CalculatorTool`, `TimeTool`

**CADKernel** (`Packages/CADKernel/`) - The only code that imports OCCTSwift/Open CASCADE (pinned to OCCTSwift `3.0.0`, arm64 only). Static `Kernel` functions over opaque `Solid` values: placed primitives, booleans, transforms, `metrics`, `tessellate` (plain `KernelMesh` triangles, Z-up). Angles are radians.

**CADSolvers** (`Packages/CADSolvers/`) - The only C++ solver code: FreeCAD's PlaneGCS (LGPL-2.1, pinned commit) with an Eigen 3.4.1 header subset (MPL-2.0), vendored unmodified under `Sources/PlaneGCS/include` with small shims for the FreeCAD/Boost headers it includes (see `Sources/PlaneGCS/VENDORED.md`; `Scripts/vendor-planegcs.sh` rebuilds the tree). `CPlaneGCS` is a C shim (opaque handle; catches every C++ exception). Swift API: `SketchSolver().solve(Sketch)` → `SketchSolution` (entities, `SketchState`: fullyConstrained / underConstrained(dof:) / overConstrained(conflicting:) / redundant / failed, DOF). Entities: point, line, circle, arc (radians, counter-clockwise), construction flag. Constraints reference entities by index and points by `SketchPointRef` (`.point/.start/.end/.center`); invalid input throws `SketchSolverError` before any C++ runs. Use `tangentAt` for tangent joints: coincident plus edge `tangent` only converges to about 1e-5. Unoptimised (debug) builds are about 20× slower than release: a 100-line sketch takes about 1.3 s in debug and 0.06 s in release. arm64 only (the Eigen subset has no SSE headers).

**CADModel** (`Packages/CADModel/`) - Pure Swift, no OCCT:

- `CADDocument` - the `.cadmodel` value: `format` 1, `units` "mm", `parameters`, `parts` (each a feature list), `assembly` (optional: `instances`, each `{id, name, part (part id), body?, placement, grounded}`; joints arrive with the assembly solver). JSON with sorted keys; `CADDocument(json:)` / `jsonData()`
- `Scalar` - every numeric field: a JSON number or an expression string (`"width / 2"`); `ParameterTable` evaluates parameters in dependency order and reports cycles and unknown names
- `Feature` - `{id, name, suppressed, kind}`; kinds: box/cylinder/sphere/cone/torus (with `Placement` in degrees and a `SolidOperation`: newBody, join/cut/intersect into a named body), boolean, transform. The n-th newBody feature in a part owns `Body<n>`
- `GeometryKernel` protocol and `RebuildEngine` - replays features off the main actor (`@concurrent`, cancellable) into an immutable `RebuildResult`: per-feature `FeatureStatus` (ok / failed / skipped(dependsOn) / suppressed), bodies with `BodyMetrics` and `BodyMesh`, evaluated parameters. A failure never aborts the rebuild
- `CADModelKernel` target - `OCCTGeometryKernel`, the adapter to CADKernel (degrees → radians happen here). `CADModelTests` use a fake kernel; `CADModelKernelTests` use the real one
- `Part.createdBodies()` / `affectedBodies()` and `FeatureKind.bodyReferences` / `renameBodyReferences` - body naming shared by the rebuild and the tools
- Sketches - `sketch` features (plane `XY`/`XZ`/`YZ` or a planar face of a body, offset; entities point/line/circle/arc with stored names `line1`…; constraints `c1`… by name, values as `Scalar`, angles in degrees) are compiled into a `SolverSketch` and solved through the `SketchSolving` protocol on every rebuild; the stored geometry is only the starting guess and is never written back. `SketchProfiles` finds closed loops of non-construction curves and nests them into regions with holes. `extrude` (distance, symmetric, throughAll, upToFace; reversed) and `revolve` (sketch line, X/Y/Z, body edge; degrees) sweep regions through `GeometryKernel.extrude`/`revolve`; faces are named `Extrude1.side[Sketch1.line3]`, `Extrude1.start`, `Extrude1.end`. `PartResult.sketches` carries each solved sketch (frame, entities, `SketchSolveState`, profiles). Over-constrained or failed sketches fail and their users are skipped; `RebuildEngine(kernel:sketchSolver:)` without a solver fails every sketch
- Assemblies - after the parts rebuild, `AssemblyBuilder` moves each instance's part bodies with `GeometryKernel.transform` (the part is built once, however often it is placed); meshes and topology are moved in Swift by `RigidTransform`, metrics come from the kernel. `RebuildResult.assembly` holds an `InstanceResult` per instance (status ok / failed(reason), transform, bodies in assembly coordinates). `ModelGeometry` measures bodies by `BodyKey(owner: .part(id) | .instance(id), body:)`. `InstanceResult.element(_:_:body:parameters:)` resolves the part's face and edge names on an instance, and `frame(face:edge:body:parameters:)` / `GeometryFrame` derive an origin and axes from a face and an optional edge, for joints
- `CADModelSolvers` target - `PlaneGCSSketchSolver`, the adapter to CADSolvers; `CADModelSolversTests` run sketches through PlaneGCS and OCCT together

**CADAssistantTools** (`Packages/CADAssistantTools/`) - Headless agent surface over CADModel (no UI, no OCCT import):

- `CADSession` - `@MainActor @Observable`; owns a `CADDocument`, a rebuild engine for any `GeometryKernel` and the latest `RebuildResult`. `apply(_:actionName:)` commits an edit (calls `onCommit`, then rebuilds); `adopt(_:)` takes over a host change at once, `load(_:)` adopts and rebuilds. Callers share one running rebuild, which only a newer document cancels; a rebuild of an older document never replaces a newer result
- `DocumentListing` - the compact text listing (parameters with values; per part, one line per feature: name, summary with expressions, → body, status). `CADSession.assistantContext()` returns it as `ListingContext`, readable from any isolation
- Tools (`CADTools.all(session:)`): `get_listing`, `find_geometry`, `measure`, `render_views`, `set_parameter`, `add_feature` (incl. extrude and revolve), `edit_feature`, `delete_feature`, `rename_feature`, `suppress_feature`, `add_sketch`, `edit_sketch`, `get_sketch`, `add_part`, `rename_part`, `delete_part`, `add_instance`, `edit_instance`, `delete_instance`. `measure` and `find_geometry` take `{"instance": …}` operands in assembly coordinates; `render_views` shows the assembly when it has instances (`show: parts|assembly`). Pass `sketchSolver: PlaneGCSSketchSolver()` to `CADSession` wherever sketches must build (the app uses `CADSession.forApp(document:)`). Every write is one commit: it is validated first (unknown names, duplicates, bad arguments, and any expression that would newly fail are refused with nothing changed), body references are renumbered when body-creating features move, and the result reports the feature's status, status changes elsewhere, every body's validity/volume/bounds and the changed listing lines
- `CADAssistantPrompt.system` / `.configuration` - the modelling system prompt (mm, degrees, check statuses after each write) with per-message context
- Tests use a fake kernel, plus `OCCTGeometryKernel` for integration and a scripted `LLMProvider` driving the `Assistant` loop
- `CADBench` (library) and `cadbench` (executable, `Sources/CADBenchCLI`) in the same package: task loading (`Bench/tasks/<id>/`), the `Grader` (gate, counts, bounds, volume, parameters, feature counts, instance count and bounds, no interference between instances, overlap with a reference, unchanged-elsewhere), the headless `BenchRunner` with a usage-recording provider, and the pass@k report. How to run it and add tasks: `Bench/README.md`

**3DModellerApp** - The main application:

- `CADModelDocument` - `ReferenceFileDocument` for `.cadmodel` files holding a `CADDocument` value; `edit(_:undoManager:_:)` registers the previous value on the window's `UndoManager` (Edit ▸ Undo, ⌘Z)
- `ContentView` - owns a `CADSession`; `.task(id: document.model)` calls `session.load`, so each edit cancels the previous rebuild. `CADModelDocument.connect(_:undoManager:)` routes session commits through `edit`, one named undo step per tool call, and hands every other change (UI edit, undo, redo) to `session.adopt` synchronously through `CADModelDocument.onChange`
- `FeatureOutlineView` (parameters, parts → features with status icons; context menu Suppress/Delete; an Assembly section with instances), `FeatureInspectorView` and `InstanceInspectorView` (read-only), `ModelStatisticsView`
- `Viewport3DView` + `ViewportScene` - draws the result's meshes: the parts, or the assembly's instances (`ViewportContent`; the assembly when there are instances, switched by a picker or by selecting a feature or instance); `ViewportFrame` converts model millimetres, Z-up, to RealityKit metres, Y-up
- Assistant: `CADTools.all(session:)` with the listing as per-message context (`CADAssistantPrompt.configuration`); the generic SwiftUIAssistantTools are no longer registered

### Key Data Flow

1. The document opens → `CADModelDocument` decodes `CADDocument`
2. `ContentView` loads it into its `CADSession`, which rebuilds off the main actor → `RebuildResult`
3. The outline, inspector, status bar and viewport read `session.result`
4. A UI edit (`CADModelDocument.edit`) changes the value and registers undo → the task calls `session.load` → rebuild
5. The assistant (`Assistant.send()` → `LLMProvider` → CAD tool) edits through `CADSession.apply` → `onCommit` → `CADModelDocument.edit` (undo step) → rebuild; the tool result reports statuses, bodies and listing changes

### Important Patterns

- The document is a value; every edit goes through `CADModelDocument.edit` with an action name, including assistant edits (via `CADSession.onCommit`)
- Body names are ordinal (`Body<n>` = n-th newBody feature). Tool edits that add, delete or change a body-creating feature renumber later references to keep them on the same creating feature, and refuse the edit if a used body would disappear
- Claude Opus 5.5 always thinks, and its thinking blocks must go back to the API unchanged. `ClaudeProvider` keeps each response's content blocks in `Message.rawContent` and replays them verbatim. Never rebuild or edit an assistant turn that has `rawContent`
- Only `CADKernel` imports OCCTSwift; every OCCT call runs inside `OCCTSerial.withLock {}`
- Only `CADSolvers` contains C++ solver code; vendored files are never edited by hand (change the shims or the pins)

## Project Configuration

- Xcode project generated via XcodeGen (`project.yml`)
- macOS 26.0 deployment target
- Swift 6.0 with strict concurrency
- Document type: `com.example.3dmodeller.cadmodel` (`.cadmodel` extension, conforms to `public.json`)
