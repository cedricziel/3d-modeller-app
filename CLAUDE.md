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

# Run a single test
xcrun swift test --filter SwiftUIAssistantTests.AssistantTests/testSendMessage
```

Always use `xcrun swift`, not bare `swift`: the `swift` on `$PATH` may be a toolchain that doesn't match the Xcode SDK and fails or hangs.

## Architecture

This is an AI-first parametric CAD app for macOS. A document holds parameters and parts with feature trees; a rebuild engine replays the features through the Open CASCADE kernel. The chat assistant will edit documents through typed tools (next layer; see `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md`).

### Package Structure

**SwiftUIAssistant** (`Packages/SwiftUIAssistant/`) - Standalone, reusable library for adding AI assistant capabilities to any SwiftUI app:

- `LLMProvider` protocol - Abstraction for AI backends (Claude implemented; `ClaudeProvider` defaults to `claude-opus-5-5`, effort `medium`)
- `AssistantTool` protocol - Define executable tools the AI can invoke
- `Assistant` class - Orchestrates LLM calls and tool execution loops
- `AssistantContext` protocol - Host app provides scene state to AI
- SwiftUI views: `AssistantPanel`, `AssistantView`, `MessageBubbleView`, etc.

**SwiftUIAssistantTools** (`Packages/SwiftUIAssistantTools/`) - Common `AssistantTool`s: `FetchTool`, `CalculatorTool`, `TimeTool`

**CADKernel** (`Packages/CADKernel/`) - The only code that imports OCCTSwift/Open CASCADE (pinned to OCCTSwift `3.0.0`, arm64 only). Static `Kernel` functions over opaque `Solid` values: placed primitives, booleans, transforms, `metrics`, `tessellate` (plain `KernelMesh` triangles, Z-up). Angles are radians.

**CADModel** (`Packages/CADModel/`) - Pure Swift, no OCCT:

- `CADDocument` - the `.cadmodel` value: `format` 1, `units` "mm", `parameters`, `parts` (each a feature list), `assembly` (reserved, `null`). JSON with sorted keys; `CADDocument(json:)` / `jsonData()`
- `Scalar` - every numeric field: a JSON number or an expression string (`"width / 2"`); `ParameterTable` evaluates parameters in dependency order and reports cycles and unknown names
- `Feature` - `{id, name, suppressed, kind}`; kinds: box/cylinder/sphere/cone/torus (with `Placement` in degrees and a `SolidOperation`: newBody, join/cut/intersect into a named body), boolean, transform. The n-th newBody feature in a part owns `Body<n>`
- `GeometryKernel` protocol and `RebuildEngine` - replays features off the main actor (`@concurrent`, cancellable) into an immutable `RebuildResult`: per-feature `FeatureStatus` (ok / failed / skipped(dependsOn) / suppressed), bodies with `BodyMetrics` and `BodyMesh`, evaluated parameters. A failure never aborts the rebuild
- `CADModelKernel` target - `OCCTGeometryKernel`, the adapter to CADKernel (degrees → radians happen here). `CADModelTests` use a fake kernel; `CADModelKernelTests` use the real one

**3DModellerApp** - The main application:

- `CADModelDocument` - `ReferenceFileDocument` for `.cadmodel` files holding a `CADDocument` value; `edit(_:undoManager:_:)` registers the previous value on the window's `UndoManager` (Edit ▸ Undo, ⌘Z)
- `ContentView` - rebuilds with `.task(id: document.model)`, so each edit cancels the previous rebuild
- `FeatureOutlineView` (parameters, parts → features with status icons; context menu Suppress/Delete), `FeatureInspectorView` (read-only), `ModelStatisticsView`
- `Viewport3DView` + `ViewportScene` - draws the result's meshes; `ViewportFrame` converts model millimetres, Z-up, to RealityKit metres, Y-up
- Assistant tools: only the generic `FetchTool`, `CalculatorTool`, `TimeTool` until the CAD tools land

### Key Data Flow

1. The document opens → `CADModelDocument` decodes `CADDocument`
2. `ContentView` runs `RebuildEngine.rebuild` off the main actor → `RebuildResult`
3. The outline, inspector, status bar and viewport read the result
4. An edit (`CADModelDocument.edit`) changes the value and registers undo → the rebuild task restarts
5. The assistant loop (`Assistant.send()` → `LLMProvider` → `AssistantTool.execute()`) runs beside it, currently with generic tools only

### Important Patterns

- The document is a value; every edit goes through `CADModelDocument.edit` with an action name
- Claude Opus 5.5 always thinks, and its thinking blocks must go back to the API unchanged. `ClaudeProvider` keeps each response's content blocks in `Message.rawContent` and replays them verbatim. Never rebuild or edit an assistant turn that has `rawContent`
- Only `CADKernel` imports OCCTSwift; every OCCT call runs inside `OCCTSerial.withLock {}`

## Project Configuration

- Xcode project generated via XcodeGen (`project.yml`)
- macOS 26.0 deployment target
- Swift 6.0 with strict concurrency
- Document type: `com.example.3dmodeller.cadmodel` (`.cadmodel` extension, conforms to `public.json`)
