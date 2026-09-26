---
name: verify
description: Build, launch and drive the 3D Modeller macOS app to verify a change at runtime.
---

# Verifying 3D Modeller changes

## Build and launch

```bash
xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp -configuration Debug -derivedDataPath <scratch>/dd build
open -a "<scratch>/dd/Build/Products/Debug/3D Modeller.app" <scratch>/plate.cadmodel
```

Bundle id: `com.example.3dmodeller`. Open a hand-written `.cadmodel` rather than starting empty. It is plain JSON (`CADDocument`); `id` fields may be left out. A plate with a hole plus a feature that is meant to fail:

```json
{
  "format": 1, "units": "mm", "assembly": null,
  "parameters": [{ "name": "t", "expression": 10 }, { "name": "hole_r", "expression": "t / 2" }],
  "parts": [{ "name": "Plate", "features": [
    { "name": "Base", "kind": { "type": "box", "width": 60, "depth": 40, "height": "t" } },
    { "name": "Hole", "kind": { "type": "cylinder", "radius": "hole_r", "height": "t",
      "placement": { "translation": { "x": 30, "y": 20 } }, "operation": { "mode": "cut", "body": "Body1" } } },
    { "name": "BadCone", "kind": { "type": "cone", "bottomRadius": 3, "topRadius": 3, "height": 5 } }
  ] }]
}
```

## Surfaces

- **Load:** opening a file decodes `CADDocument` and rebuilds off the main actor. The viewport frames the model on the first result. Units are millimetres, Z up in the file, Y up on screen.
- **Outline (left):** parameters with their values, then each part's features with a status icon (✓ ok, ✗ failed, ↩ skipped, ⏸ suppressed). Hover the icon for the reason (e.g. `failed: cone radii must differ; use a cylinder for equal radii`).
- **Inspector (right, Properties tab):** the selected feature, read-only: type, body, status, dimensions, placement, operation.
- **Status bar (bottom):** bodies, triangles, and failed features when any.
- **Edits without an API key:** right-click a feature → Suppress/Unsuppress or Delete. Each is one undo step; Edit ▸ Undo shows its name (`Undo Suppress BadCone`).
- **Save:** ⌘S or autosave rewrites the file with sorted keys and generated ids; read it back with `python3 -m json.tool`.
- The assistant panel needs an API key and has only the fetch, calculator and time tools until the CAD tools land.

## Gotchas

- A file with another `format` or `units`, or an unknown feature `type`, does not open (decoding throws `DocumentError` or `DecodingError`).
- Outline context menus (Suppress/Delete) need a right-click, which background `app_click` refuses; take full-screen control for them. Read-only checks (outline icons, status bar, viewport) work from `app_screenshot` alone.
- The status bar reads e.g. `1 bodies · 144 triangles · 1 failed` for the sample above.

## When you're done

1. Close the debug app: `pkill -f "dd/Build/Products/Debug/3D Modeller.app"`.
2. Let go of screen control, even if the check failed or you stopped early: call `app_release` (no arguments) to drop every app lock, and `release_full_control` if you took full-screen control. Don't leave the user's screen locked or glowing after verification.
