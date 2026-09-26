# 3D Modeller

An AI-first 3D modeling application for macOS where users interact primarily through a chat assistant that has full autonomous access to create, manipulate, and modify 3D models.

## Features

- **AI-Powered Modeling** - Chat with an assistant to create and modify 3D objects
- **RealityKit Viewport** - Hardware-accelerated 3D rendering with orbit, zoom, and pan controls
- **Primitive Shapes** - Box, sphere, cylinder, cone, plane, torus
- **Material System** - Color, metallic, and roughness properties
- **Document-Based** - Save and load scenes as `.scene3d` files
- **Undo/Redo** - Full history support for all operations

## Requirements

- macOS 26.0+
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
```

### Configure API Key

1. Launch the app
2. Open Settings (⌘,)
3. Enter your Anthropic API key

## Usage

Type natural language commands in the assistant panel:

- "Create a red cube"
- "Add a blue sphere next to it"
- "Make the cube bigger"
- "Rotate the sphere 45 degrees"
- "Delete the cube"

The assistant has access to these tools:

- `create_primitive` - Create box, sphere, cylinder, cone, plane, torus
- `transform_entity` - Move, rotate, scale objects
- `set_material` - Change color, metallic, roughness
- `duplicate_entity` - Copy objects
- `delete_entity` - Remove objects
- `query_scene` - List and filter scene contents
- `fetch`, `calculator`, `time` - General-purpose helpers from `SwiftUIAssistantTools`

## Architecture

```
├── Packages/
│   ├── SwiftUIAssistant/     # Reusable AI assistant library
│   │   ├── Core/             # Assistant orchestration
│   │   ├── Providers/        # LLM backends (Claude)
│   │   ├── Tools/            # Tool protocol & registry
│   │   └── Views/            # Chat UI components
│   └── SwiftUIAssistantTools/ # Common tools (fetch, calculator, time)
│
└── 3DModellerApp/            # Main application
    ├── App/                  # Entry point, global state
    ├── Scene/                # RealityKit scene management
    ├── Tools/                # AI tool implementations
    ├── Context/              # Scene context for AI
    └── Views/                # UI components
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
| File Format | JSON (Codable) |

## License

MIT
