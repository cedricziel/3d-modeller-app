# 3D Modeller

An AI-first parametric CAD application for macOS. A model is a list of parameters and features that the app rebuilds with the Open CASCADE kernel; a chat assistant will build and change models through typed tools.

## Features

- **Parametric documents** - `.cadmodel` files: plain, key-sorted JSON in millimetres
- **Parameters** - Named values and expressions (`width / 2 + t`) usable in every numeric field
- **Feature trees** - Box, cylinder, sphere, cone and torus with placements; booleans (union, subtract, intersect) and transforms; each solid can start a new body or join, cut or intersect an existing one
- **Robust rebuild** - Each feature reports ok, failed (with the reason), skipped (with the feature it depends on) or suppressed; one failure never stops the rest
- **Exact CAD geometry** - Solids built by the Open CASCADE kernel and drawn in a RealityKit viewport
- **Undo/Redo** - Document edits go through the window's undo history (Edit ▸ Undo, ⌘Z)
- **AI assistant** - Chat panel backed by Claude; modelling tools arrive in the next release

## Requirements

- macOS 26.0+ on Apple Silicon
- Xcode 26+ (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An Anthropic API key (for Claude integration)

## Getting Started

### Build with Xcode

```bash
# Generate the Xcode project
xcodegen generate

# Open in Xcode
open 3DModellerApp.xcodeproj
```

Then build and run with ⌘R.

### Build with Swift Package Manager

```bash
xcrun swift build
xcrun swift run 3DModellerApp
```

Use `xcrun swift`, not a bare `swift`, so the toolchain matches the active Xcode SDK.

### Run Tests

```bash
# App tests
xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test

# Package tests
(cd Packages/SwiftUIAssistant && xcrun swift test)
(cd Packages/SwiftUIAssistantTools && xcrun swift test)
(cd Packages/CADKernel && xcrun swift test)
(cd Packages/CADModel && xcrun swift test)
```

### Configure API Key

1. Launch the app
2. Open Settings (⌘,)
3. Enter your Anthropic API key

## Usage

Open or create a `.cadmodel` document. A small example, a plate with a hole:

```json
{
  "format": 1,
  "units": "mm",
  "parameters": [{ "name": "t", "expression": 10 }],
  "parts": [
    {
      "name": "Plate",
      "features": [
        { "name": "Base", "kind": { "type": "box", "width": 60, "depth": 40, "height": "t" } },
        {
          "name": "Hole",
          "kind": {
            "type": "cylinder", "radius": 5, "height": "t",
            "placement": { "translation": { "x": 30, "y": 20 } },
            "operation": { "mode": "cut", "body": "Body1" }
          }
        }
      ]
    }
  ],
  "assembly": null
}
```

The outline lists parameters and features with their rebuild status; select a feature to see its values in the inspector. Right-click a feature to suppress or delete it. Until the CAD tools land, the assistant can only use the general-purpose `fetch`, `calculator` and `time` tools.

## Architecture

```
├── Packages/
│   ├── SwiftUIAssistant/      # Reusable AI assistant library
│   ├── SwiftUIAssistantTools/ # Common tools (fetch, calculator, time)
│   ├── CADKernel/             # Open CASCADE geometry (the only OCCT importer)
│   └── CADModel/              # Document, parameters, features, rebuild engine
│                              # (+ CADModelKernel: the CADKernel adapter)
│
└── 3DModellerApp/             # Main application
    ├── App/                   # Entry point, global state
    ├── Document/              # .cadmodel document type and undo
    ├── Viewport/              # RealityKit scene built from rebuild results
    └── Views/                 # Outline, inspector, viewport, assistant UI
```

### SwiftUIAssistant

A standalone Swift package that can be reused to add AI assistant capabilities to any SwiftUI app. Key protocols:

- `LLMProvider` - Pluggable AI backend interface
- `AssistantTool` - Define tools the AI can execute
- `AssistantContext` - Provide app state to the AI

`ClaudeProvider` defaults to Claude Opus 5.5 (`claude-opus-5-5`) at `medium` effort. Pass `model:` and `effort:` to change them.

### SwiftUIAssistantTools

Ready-made `AssistantTool`s any host app can register: `FetchTool`, `CalculatorTool`, `TimeTool`.

### Technology Stack

| Component | Technology |
|-----------|------------|
| UI Framework | SwiftUI |
| 3D Rendering | RealityKit |
| AI Integration | Claude API |
| State Management | @Observable, @MainActor |
| Geometry | Open CASCADE via OCCTSwift |
| File Format | JSON (Codable), `.cadmodel` |

## Acknowledgements

This app uses [Open CASCADE Technology](https://dev.opencascade.org) (LGPL 2.1 with the Open CASCADE Exception) through [OCCTSwift](https://github.com/SecondMouseAU/OCCTSwift) (LGPL 2.1). See [NOTICE](NOTICE).

## License

Licensed under the [Apache License 2.0](LICENSE).
