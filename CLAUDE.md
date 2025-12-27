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

# Build via Swift Package Manager (alternative)
swift build

# Run SwiftUIAssistant tests
cd Packages/SwiftUIAssistant && swift test

# Run a single test
swift test --filter SwiftUIAssistantTests.AssistantTests/testSendMessage
```

## Architecture

This is an AI-first 3D modeling macOS app where users interact primarily through a chat assistant that autonomously creates and manipulates 3D objects.

### Two-Package Structure

**SwiftUIAssistant** (`Packages/SwiftUIAssistant/`) - Standalone, reusable library for adding AI assistant capabilities to any SwiftUI app:

- `LLMProvider` protocol - Abstraction for AI backends (Claude implemented)
- `AssistantTool` protocol - Define executable tools the AI can invoke
- `Assistant` class - Orchestrates LLM calls and tool execution loops
- `AssistantContext` protocol - Host app provides scene state to AI
- SwiftUI views: `AssistantPanel`, `AssistantView`, `MessageBubbleView`, etc.

**3DModellerApp** - The main application consuming SwiftUIAssistant:

- `SceneManager` - Central RealityKit scene management with undo/redo
- `SceneDocument` - FileDocument for `.scene3d` files (JSON-based)
- Tools implementing `AssistantTool`: `CreatePrimitiveTool`, `TransformEntityTool`, `DeleteEntityTool`, `SetMaterialTool`, `DuplicateEntityTool`, `QuerySceneTool`

### Key Data Flow

1. User sends message → `Assistant.send()`
2. Assistant calls `LLMProvider.sendMessage()` with tools and context
3. LLM returns tool calls → Assistant executes via `AssistantTool.execute()`
4. Tools call `SceneManager` methods (wrapped in `MainActor.run`)
5. Loop continues until LLM returns text-only response

### Important Patterns

- All `SceneManager` properties are `@MainActor` isolated
- Tool execute methods parse arguments first, then wrap scene mutations in `await MainActor.run {}`
- `CADEntity` wraps RealityKit `Entity` with app-specific metadata
- Scene serialization uses `EntityData`, `TransformData`, `MaterialData`, `ColorData` (all Codable)

## Project Configuration

- Xcode project generated via XcodeGen (`project.yml`)
- macOS 26.0 deployment target
- Swift 6.0 with strict concurrency
- Document type: `com.example.3dmodeller.scene` (`.scene3d` extension)
