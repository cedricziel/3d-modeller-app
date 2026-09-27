# CAD 06: Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The agent can check its own work: write results carry everything the spec lists in a bounded size, a `measure` tool answers distance, angle, size and interference questions with kernel precision, and a `render_views` tool returns pictures of the model that reach the model as image content.

**Architecture:** `SwiftUIAssistant` learns image content in tool results (`ToolImage`, `ToolExecutionResult.images`, `Message.images`, `ClaudeProvider` tool-result content blocks). `CADKernel` adds minimum distance and sub-shape bounds; `CADModel` exposes them through `GeometryKernel` and a type-erased `ModelGeometry` that the rebuild produces next to `RebuildResult`, so `CADSession` can measure without a second replay. `CADAssistantTools` adds `MeasureTool`, a headless software rasteriser (`ViewRenderer`, pure Swift plus ImageIO for PNG) and `RenderViewsTool`; `CADBench` writes the final renders of each run.

**Tech Stack:** Swift 6 (tools 6.1 for OCCT packages, 6.0 for SwiftUIAssistant), Swift Testing, OCCTSwift 3.0.0 (`Shape.distance(to:)` = `BRepExtrema_DistShapeShape`, `Shape.vertex(at:)`, `Shape.boundingBoxOptimal()`), CoreGraphics + ImageIO (PNG), Anthropic Messages API tool-result image blocks.

**Spec:** `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md` (sections "Agent tools", "Benchmark", PR-stack row 6). Previous layer: `docs/superpowers/plans/2026-09-26-cad-05-naming.md`.

## Global Constraints

- macOS 26, Apple Silicon only (`ARCHS: arm64`), Swift 6 strict concurrency. Use `xcrun swift`, never bare `swift`.
- Only `CADKernel` imports OCCTSwift. Every OCCT call runs inside `OCCTSerial.withLock {}`. No C++ exception may reach Swift; failures are typed errors.
- The agent-facing surface (document, rebuild, tools) runs without the app or any UI.
- Millimetres everywhere; angles in degrees.
- Tests use Swift Testing. Semantic commits, one concern each, no "and" in the subject, no co-author lines. Comments only for a non-obvious why.
- Disk is tight: derived data and clean builds go to the scratchpad and are deleted afterwards. No two targets in one package may differ only by case.

## Rulings

- **Ruling: a pure-Swift software rasteriser renders the views, not RealityKit or Metal.** It z-buffers the tessellated body meshes with flat two-sided Lambert shading and draws feature lines (mesh edges on a crease above 35° or an open border), then encodes PNG with ImageIO. It needs no window server, GPU or Metal device, so it runs the same in the app, `cadbench` and `swift test` on CI runners. Cost if wrong: the pictures look plainer than a RealityKit render (no anti-aliasing, no shadows).
- **Ruling: four separate 512×512 PNGs, each after a text caption, not one tiled image.** Captions carry the view name, the viewing direction and the scale (mm per pixel), which a tiled image would need drawn text for. Four 512² images cost about as many tokens as one 1024² tile (≈350 each). The tool takes an optional `views` subset to spend less. Cost if wrong: four content blocks instead of one per call.
- **Ruling: each view is framed on its own.** The projected bounding box of all rendered bodies fills the image with a 6 % margin, square pixels; the caption states mm per pixel. Cost if wrong: views are not at the same scale, which the captions make explicit.
- **Ruling: views follow the model's axes, Z up.** `top` looks down −Z (+X right, +Y up), `front` looks along +Y at the −Y face (+X right, +Z up), `right` looks along −X at the +X face (+Y right, +Z up), `iso` looks from (+1, −1, +1) (Z up). Cost if wrong: none; captions name the directions.
- **Ruling: body colours come from a fixed eight-colour palette in body order across parts,** named in the tool's text (`Body1 (Plate) blue`). Cost if wrong: after eight bodies colours repeat.
- **Ruling: `ClaudeProvider` sends a tool result with images as a content array** — the message text block, then per image an optional caption text block and an `image` block with `source {type: base64, media_type, data}`. Results without images keep today's plain string content. Cost if wrong: none; the API accepts both forms.
- **Ruling: images stay in the history.** Every later request re-sends them. Dropping old images is left for later (see Deferred). Cost if wrong: long sessions with many renders pay for old images.
- **Ruling: measure operands are objects** `{"part"?, "body"?, "face"?, "edge"?, "point"?}`: a body alone, a face or edge reference of a body (name or filter, which must match exactly one), or a point `[x, y, z]`. Cost if wrong: the model must write objects instead of bare strings; the refusal shows the form.
- **Ruling: `measure` kinds are `distance`, `angle`, `size` and `interference`.** `distance` is the kernel's minimum distance with the closest points (0 when touching or overlapping). `angle` takes planar faces (normal) and straight edges (direction): face–face is the angle between the outward normals (0–180°), edge–edge the angle between the lines (0–90°), face–edge the angle between the edge and the plane (0–90°). `size` of a body gives volume, surface area, bounds and extent, face and edge counts; of a face its type, area, centroid, normal or radius and bounds; of an edge its type, length, ends or radius. `interference` of two bodies gives the intersection volume, and the clearance when they do not overlap. Cost if wrong: extensions are additive.
- **Ruling: interference is `vol(a) + vol(b) − vol(a ∪ b)` through the existing `boolean`, clamped to 0 below 1e−6 of the smaller volume,** as the grader already does; no new kernel call. Cost if wrong: cancellation error on very large bodies (relative 1e−9).
- **Ruling: the rebuild keeps the kernel bodies for measuring.** `RebuildEngine.build(_:)` returns `RebuiltModel { result, geometry }`; `CADSession` stores the geometry beside the result, so `measure` never replays. Cost if wrong: the session holds OCCT shapes of the latest rebuild in memory.
- **Ruling: write results list bodies that are new, changed or have problems in full; unchanged valid bodies share one `Unchanged bodies: …` line and removed ones a `Removed bodies: …` line; body lines gain `N faces, M edges`; body lines, status changes and listing changes each stop after 30 lines.** Cost if wrong: the model must remember an unchanged body's numbers from earlier results or call `measure`.

- **Ruling (execution): feature lines are border and crease edges only, no silhouettes.** OCCT's per-face triangulations do not share a winding, so front/back facing is unreliable; creases use the unsigned angle, which misses folds sharper than 145° (knife edges). Cost if wrong: very sharp wedges lose their outline; shading still shows them.
- **Ruling (execution): a body is "unchanged" only when its line is identical, no feature that builds, changes or reads it changed, and none of those features' numeric fields changed value through a parameter.** The reviewer showed a moved hole keeps volume and bounds. Cost if wrong: a few more bodies are listed in full.
- **Ruling (execution): `measure` and `render_views` compute in `@concurrent` functions** after reading the session on the main actor. Cost if wrong: none.
- **Ruling (execution): interference checks the clearance first** and runs the union only when the bodies touch; the overlap cut-off is 1e−5 of the smaller volume. Cost if wrong: a real overlap below 1e−5 relative reads as touching.
- **Ruling (execution): parts sharing a name are refused by `measure`**, since `ModelGeometry` keys bodies by part name. Face and edge labels read `Plate.top of Body1 (Plate)`. Cost if wrong: none until `add_part` (PR 9) must keep part names unique.
- **Measured (execution): a cut in a ten-body document returns 382 characters (≈100 tokens)**; before this layer the same result listed all ten bodies (≈1,450 characters).

## Review Focus

1. A body that failed or has no mesh while `render_views` runs. Expected: the other bodies render, the text names the missing body; no bodies at all gives a text-only success. Pinned in Task 6 (`rendersWithoutBrokenBody`, `nothingToRender`).
2. A measure reference that matches several faces or none. Expected: refusal listing candidates, nothing measured. Pinned in Task 5 (`ambiguousOperand`).
3. `angle` between a cylinder face or a circular edge. Expected: refusal naming what `angle` accepts. Pinned in Task 5 (`angleRefusals`).
4. Interference of two bodies that do not touch. Expected: 0 mm³ and the clearance, no kernel error. Pinned in Task 5 (`disjointInterference`).
5. A text-only tool result after an image one in the same conversation. Expected: the text one is still a plain string content. Pinned in Task 1 (`mixedToolResults`).

## File Structure

`Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/`: `Tools/ToolImage.swift` (new), `Tools/ToolExecutionResult.swift`, `Conversation/Message.swift`, `Core/Assistant.swift`, `Providers/ClaudeProvider.swift` (modify). Tests: `ClaudeProviderTests.swift`, `AssistantTests.swift`.

`Packages/CADKernel/Sources/CADKernel/Kernel+Measure.swift` (new); `Tests/CADKernelTests/MeasureTests.swift` (new).

`Packages/CADModel/Sources/CADModel/`: `GeometryKernel.swift` (distance, bounds, `GeometryOperand`, `DistanceMeasurement`, `Bounds`), `ModelGeometry.swift` (new), `RebuildEngine.swift` (`build`). `CADModelKernel/OCCTGeometryKernel.swift`. Tests: fake kernel, `ModelGeometryTests.swift` (new), `OCCTGeometryKernelTests.swift`.

`Packages/CADAssistantTools/Sources/CADAssistantTools/`: `CADSession.swift` (geometry), `WriteReport.swift`, `MeasureTool.swift` (new), `MeasureOperand.swift` (new), `Rendering/ViewRenderer.swift`, `Rendering/Rasterizer.swift`, `Rendering/PNG.swift` (new), `RenderViewsTool.swift` (new), `CADTools.swift`, `CADAssistantPrompt.swift`. `CADBench/BenchRunner.swift`, `CADBench/ResultWriter.swift`, `CADBench/Transcript.swift`. Tests: `WriteReportTests.swift`, `MeasureToolTests.swift`, `ViewRendererTests.swift`, `RenderViewsToolTests.swift` (new), `BenchRunnerTests.swift`, `BenchReportTests.swift`.

---

### Task 1: Image content in tool results (SwiftUIAssistant)

**Interfaces — Produces:**

```swift
public struct ToolImage: Sendable, Equatable {
    public let mediaType: String      // "image/png"
    public let data: Data
    public let caption: String?
    public init(mediaType: String = "image/png", data: Data, caption: String? = nil)
}
public struct ToolExecutionResult { …; public let images: [ToolImage]
    public init(success: Bool, message: String, data: [String: JSONValue]? = nil, images: [ToolImage] = [])
    public static func success(_ message: String, data: [String: JSONValue]? = nil, images: [ToolImage] = []) -> Self }
public struct Message { …; public let images: [ToolImage]
    public static func toolResult(toolCallId: String, content: String, images: [ToolImage] = []) -> Message }
```

`Assistant` passes `result.images` into the tool-result message. `ClaudeProvider.formatMessage(.toolResult)`:

```swift
let content: Any = message.images.isEmpty ? message.content : [["type": "text", "text": message.content]]
    + message.images.flatMap { image -> [[String: Any]] in
        (image.caption.map { [["type": "text", "text": $0]] } ?? [])
            + [["type": "image", "source": ["type": "base64", "media_type": image.mediaType,
                                             "data": image.data.base64EncodedString()]]]
    }
```

- [ ] Step 1: failing tests — `ClaudeProviderTests.imageToolResult` (content array: text, caption, image with base64 of the bytes), `mixedToolResults` (a text-only result in the same request stays a string); `AssistantTests.toolImagesReachHistory` (a mock tool returning an image → the tool-result message carries it).
- [ ] Step 2: `xcrun swift test --package-path Packages/SwiftUIAssistant` fails to compile.
- [ ] Step 3: implement. Step 4: suite passes.
- [ ] Step 5: commit `feat(assistant): send images in tool results`.

### Task 2: Minimum distance and bounds in CADKernel

**Interfaces — Produces:**

```swift
public enum SubShape: Sendable, Equatable { case whole, face(Int), edge(Int) }
public struct Distance: Sendable, Equatable { public let value: Double; public let pointA, pointB: SIMD3<Double> }
extension Kernel {
    public static func distance(_ a: Solid, _ sa: SubShape, _ b: Solid, _ sb: SubShape) throws -> Distance
    public static func distance(from point: SIMD3<Double>, to solid: Solid, _ sub: SubShape) throws -> Distance
    public static func bounds(of solid: Solid, _ sub: SubShape) throws -> (min: SIMD3<Double>, max: SIMD3<Double>)
}
```

Sub-shapes index `subShapes(ofType: .face|.edge)` (the topology order). Out of range → `.invalidDimensions("face 9 does not exist; the solid has 6 faces")`; OCCT answers nil → `.operationFailed("measure the distance")` / `("measure the bounds")`.

- [ ] Step 1: failing `MeasureTests` — two unit cubes 5 apart along X: 5, closest points x=1 and x=6; top face of a 10-cube to a point (5,5,20): 10; edge to edge; overlapping boxes: 0; face bounds of the top of a 10×20×30 box: z 30…30; out-of-range index throws.
- [ ] Step 2–4: `xcrun swift test --package-path Packages/CADKernel --scratch-path Packages/CADModel/.build --filter Measure`, implement with `Shape.distance(to:)`, `Shape.vertex(at:)`, `boundingBoxOptimal()`, run the kernel suite.
- [ ] Step 5: commit `feat(kernel): measure distances between solids, faces and edges`.

### Task 3: Measuring through the model

**Interfaces — Produces (CADModel):**

```swift
public enum GeometryOperand<Body: Sendable>: Sendable { case point(SIMD3<Double>), body(Body), face(Body, Int), edge(Body, Int) }
public struct DistanceMeasurement: Sendable, Equatable { public var distance: Double; public var pointA, pointB: SIMD3<Double> }
public struct Bounds: Sendable, Equatable { public var min, max: SIMD3<Double> }
protocol GeometryKernel { …
    func distance(_ a: GeometryOperand<Body>, _ b: GeometryOperand<Body>) throws -> DistanceMeasurement
    func bounds(of operand: GeometryOperand<Body>) throws -> Bounds }
public struct BodyKey: Sendable, Hashable { public var part: String; public var body: String }
public enum MeasureTarget: Sendable, Equatable { case point(SIMD3<Double>), body(BodyKey), face(BodyKey, Int), edge(BodyKey, Int) }
public struct ModelGeometry: Sendable {
    public static let empty: ModelGeometry
    public func distance(_ a: MeasureTarget, _ b: MeasureTarget) throws -> DistanceMeasurement
    public func bounds(of target: MeasureTarget) throws -> Bounds
    public func interference(_ a: BodyKey, _ b: BodyKey) throws -> Double
}
public struct RebuiltModel: Sendable { public let result: RebuildResult; public let geometry: ModelGeometry }
extension RebuildEngine { public func build(_ document: CADDocument) async throws -> RebuiltModel }  // rebuild = build().result
```

`ModelGeometry` wraps `[BodyKey: Body]` and the kernel in closures (the only place the body type is erased). Point–point distance is computed in Swift; a point operand for bounds is refused. Errors: `MeasureError(description)`.

- [ ] Step 1: failing tests — CADModel fake: `ModelGeometryTests` (unknown body → error naming it; interference by inclusion–exclusion with the fake's union volumes); real kernel `OCCTGeometryKernelTests.measureDistance` (plate with hole: hole side to plate left face = 30 − 2.75), `interference` (two overlapping 10-cubes offset 5 → 500; disjoint → 0).
- [ ] Step 2–4: implement in `OCCTGeometryKernel`, both fakes (CADModel, CADAssistantTools: bounds of the fake body, distance between bounding boxes); run CADModel and CADAssistantTools suites.
- [ ] Step 5: commit `feat(model): measure distances between rebuilt bodies`.

### Task 4: Richer, bounded write results

**Files:** `WriteReport.swift`, `CADSession.swift` (stores `geometry` from `build`); tests `WriteReportTests.swift` (new), update `AddFeatureToolTests`, `RealKernelTests`, others whose exact text changes.

Body line: `Body1 (Plate): valid closed solid, 6 faces, 12 edges, volume 24000 mm³, bounds (0, 0, 0) to (60, 40, 10)`. Unchanged valid bodies (same line before and after): `Unchanged: Body2 (Plate), Body3 (Plate)`. Removed bodies: `Removed: Body3 (Plate)`. Listing changes capped at 30 lines.

- [ ] Step 1: failing tests — counts in the line; `unchangedBodiesCollapse` (two bodies, edit one → the other in `Unchanged:`); `removedBody`; `listingDiffCapped` (a parameter change touching 40 lines shows 30 and `… 10 more changed lines; call get_listing`); `writeResultBudget`: a cut on a ten-feature document stays under 1200 characters (≈300 tokens).
- [ ] Step 2–4: implement, run the tools suites.
- [ ] Step 5: commits `feat(tools): report face and edge counts per body`, `feat(tools): keep write results bounded`.

### Task 5: `measure`

**Files:** `MeasureOperand.swift`, `MeasureTool.swift`, `CADTools.swift`, `CADSession.swift` (`currentGeometry()`); tests `MeasureToolTests.swift`.

```
measure(kind: distance|angle|size|interference, a: operand, b?: operand)
distance: "Distance 27.25 mm from Hole.side (Body1) to Plate.left (Body1); closest points (27.25, 20, 5) and (0, 20, 5)"
angle:    "Angle 90° between the normals of Plate.top and Plate.front (Body1)"
size:     "Body1 (Plate): volume 23762.4 mm³, area 5058.48 mm², bounds (0, 0, 0) to (60, 40, 10), extent 60 × 40 × 10, 7 faces, 15 edges"
interference: "Body1 and Body2 (Plate) overlap by 500 mm³" | "Body1 and Body2 (Plate) do not overlap; clearance 5 mm"
```

- [ ] Step 1: failing tests (fake kernel): operand parsing refusals (`{}`; face and edge together; point with body; unknown body lists bodies; `ambiguousOperand`), `angleRefusals` (cylinder face, circular edge, point), size of a face and a body, angle face–face 90° and 180°, edge–edge, face–edge; real kernel: distance hole ↔ left face 27.25, `disjointInterference`, overlap 500.
- [ ] Step 2–4: implement, run.
- [ ] Step 5: commit `feat(tools): measure distances, angles, sizes and interference`.

### Task 6: Headless renderer and `render_views`

**Interfaces — Produces:**

```swift
public enum ViewDirection: String, CaseIterable, Sendable { case iso, top, front, right }
public struct RenderedView: Sendable, Equatable { public let view: ViewDirection; public let png: Data; public let millimetresPerPixel: Double }
public enum ViewRenderer {
    public static let size = 512
    public static func render(_ bodies: [(mesh: BodyMesh, colour: SIMD3<Float>)], views: [ViewDirection]) -> [RenderedView]
    static func rasterize(...) -> RGBAImage   // internal, tested for pixel regions
}
public struct RenderViewsTool: AssistantTool   // name "render_views", optional views, optional part
extension CADSession { public func renderViews(_ views: [ViewDirection] = ViewDirection.allCases) async -> (text: String, views: [RenderedView]) }
```

- [ ] Step 1: failing `ViewRendererTests` — a 10-cube at (0,0,0)… (10,10,10) seen from `top` fills the centre square with the body colour (sampled pixels at the centre are shaded blue, the corners background); a box elongated in X is wider than tall in `front`; `iso` shows three shades (three visible faces); PNG decodes with ImageIO to 512×512; `RenderViewsToolTests` — result has four images with captions `iso: from +X −Y +Z …`, text names `Body1 (Plate) blue`; `views: ["top"]` gives one; unknown view refused; `rendersWithoutBrokenBody`; `nothingToRender`; real kernel plate with hole: top view has background pixels at the hole centre.
- [ ] Step 2–4: implement, run.
- [ ] Step 5: commits `feat(tools): render bodies headlessly`, `feat(tools): return rendered views to the assistant`.

### Task 7: Bench renders, prompt

- `RunRecord.renders: [RenderedView]` from the final session; `ResultWriter` writes `view-<name>.png` byte-for-byte (not redacted). `TranscriptEntry.images: [String]?` (captions).
- Prompt: `measure` and `render_views` in "Working": after a bigger change (a new part of the shape, a boolean, several edits), call render_views once and look; use measure to check a dimension the user gave rather than trusting arithmetic. Don't render after every small edit; images cost tokens.
- [ ] Step 1: failing tests — `BenchRunnerTests.completedRun` expects four renders; `BenchReportTests` writes `view-iso.png` equal to the data; prompt test contains `render_views`.
- [ ] Step 2–4: implement, run CADAssistantTools suite.
- [ ] Step 5: commits `feat(bench): keep the final renders of each run`, `docs(tools): tell the assistant to verify with renders and measurements`.

### Task 8: App build, final review

App build and tests with derived data in the scratchpad; fresh `opus` reviewer over `git merge-base cad/05-naming HEAD..HEAD`; one fix pass for Critical/Important findings; clean `swift test` of every changed package in the scratchpad.

## Deferred after the final review

- Old images stay in the conversation and are re-sent on every request; drop images from all but the latest render results when sessions get long.
- A rerun into an existing `run-N` folder leaves `view-*.png` files of an earlier run that rendered more views.
- `ModelGeometry.distance` and `OCCTGeometryKernel.distance` both handle point–point; the kernel returns a degenerate box as a point's bounds while `size` refuses points first.
- The app's chat does not show tool-result images yet.
- `ModelGeometry` should key bodies by part id once parts can be added (PR 9).

### Resolved/skipped in follow-up (`fix/deferred-review-items`)

- Fixed: rewriting a run folder removes the `view-*.png` and `final.step` an earlier write left.
- Skipped: dropping old images (a cost trade-off in the provider); the duplicate point–point distance (cosmetic); tool-result images in the chat (a feature); keying bodies by part id (already done: `BodyKey` has an owner).

## Self-review

- Spec coverage: write results (Task 4; sketch and joint states arrive with PRs 8–11), `measure` (Tasks 2, 3, 5), `render_views` as images (Tasks 1, 6), bench renders (Task 7), prompt (Task 7).
- Types: `GeometryOperand`, `ModelGeometry`, `MeasureTarget`, `BodyKey`, `RenderedView`, `ViewDirection` keep the same names in Tasks 3–7.
