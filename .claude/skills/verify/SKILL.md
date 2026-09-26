---
name: verify
description: Build, launch and drive the 3D Modeller macOS app to verify a change at runtime.
---

# Verifying 3D Modeller changes

## Build and launch

```bash
xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp -configuration Debug -derivedDataPath <scratch>/dd build
open -a "<scratch>/dd/Build/Products/Debug/3D Modeller.app" <scratch>/some.scene3d
```

Bundle id: `com.example.3dmodeller`. Open a hand-written `.scene3d` file rather than starting empty; it's plain JSON (`SceneData`), so you can seed exact transforms and materials and read the saved result back with `python3 -c 'import json; ...'`.

## Surfaces

- **Load:** opening a file runs `SceneManager.loadSceneData`. Select an object in the left outline; the right inspector shows position, scale, metallic and roughness (not rotation).
- **Save:** the document syncs on `SceneManager.revision`; macOS autosaves the file in place within a second or two, or press ⌘S. Diff the JSON against the file you wrote.
- **Edits without an API key:** inspector position/scale fields, color, metallic/roughness sliders; outline context menu has Duplicate/Delete. The assistant panel needs an API key.

## Gotchas

- Typing into inspector fields needs full-screen computer-use control; background `app_type` is refused.
- Close the debug app afterwards: `pkill -f "dd/Build/Products/Debug/3D Modeller.app"`.
