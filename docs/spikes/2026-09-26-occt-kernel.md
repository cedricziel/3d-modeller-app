# OCCT kernel spike: findings

Spec: `docs/superpowers/specs/2026-09-26-geometry-kernel.md`

## Size and build time

Release, arm64 only, `CODE_SIGNING_ALLOWED=NO`, measured on the same machine. Baseline is `origin/main` at `be0f30c`.

| | Baseline | With CADKernel |
|---|---|---|
| App bundle (`du -sk`) | 1,572 KB | 62,728 KB |
| Executable | 1.6 MB | 64.2 MB |
| App zipped (`ditto -c -k`) | not measured | 21.3 MB |
| Clean build | 16 s | 124 s |
| Incremental build after touching one app file | 3.4 s | 9.5 s |

For contributors and CI, the first build downloads the 149 MB `OCCT.xcframework.zip` (about 18 s here). Unpacked, it takes 594 MB in `.build/artifacts`. The first `xcrun swift test` in `Packages/CADKernel` takes 40 s, mostly compiling OCCTSwift's Objective-C++ bridge.

## Did it work?

Yes, end to end. `CADKernel` extrudes a rectangle, fillets its vertical edges and tessellates the result. The app turns that into a RealityKit mesh, and a block shows up upright in the viewport with smooth fillets and correct lighting. The tests confirm that blocks survive save and reload, undo and duplicate, and that older `.scene3d` files still open. The assistant can create blocks through `create_solid`, and bad input (a fillet that doesn't fit, zero or negative sizes) comes back as a readable error without changing the scene. Extrusion, fillet and the fillet-too-large error worked first time. Tessellation, orientation and the Release build each needed a fix (see Surprises).

## Surprises

- **Mesh normals from OCCTSwift are placeholders.** OCCT's triangulation has no normals unless they're computed, and OCCTSwift 3.0.0 fills in `(0, 0, 1)` for every vertex. Triangle winding is correct, since the bridge flips reversed faces. `CADKernel` computes area-weighted vertex normals itself. Worth reporting upstream.
- **No Intel slice.** OCCTSwift's xcframework is arm64 only, so the default universal Release build fails to link. The app now builds for `arm64` only. macOS 26 is the last release that supports Intel Macs, so this matters little.
- **Z-up vs Y-up.** The kernel models Z-up and RealityKit is Y-up. The conversion happens once, in `KernelMesh.meshDescriptor`, so saved entity rotations stay clean.
- **OCCT fails cleanly on an oversized fillet.** A 0.8 radius on a 1 × 1 × 1 block returns no shape, which surfaces as `KernelError.operationFailed`. No crash, and no need for extra validity checks.
- **Bounding boxes are exact enough.** `boundingBox` matched the expected extents within 1e-6, so the test tolerance didn't need loosening.
- **XcodeGen drift.** The committed `.xcodeproj` came from an older XcodeGen, so regenerating it produced unrelated format changes. These were committed separately.

## Follow-ups

- A block whose recipe no longer builds is silently skipped on load and duplicate (`try?` in `SceneManager`). The feature-tree design needs a visible "failed to rebuild" state.
- Kernel work runs on the main actor inside `createSolid`. Move it off-main before operations get expensive.
- The status bar's triangle count uses a fixed guess per type, which is 12 for a block, not the real mesh count.
- Edit ▸ Undo doesn't call `SceneManager.undo()` at all; nothing in the UI does. This predates the spike and is unrelated to it.
- Report the placeholder-normals issue to OCCTSwift.

## Verdict

Keep OCCTSwift, pinned at `3.0.0` behind `CADKernel`. It worked with little friction. The one real bug (normals) was easy to work around in our own layer, and the boundary held: nothing outside `Packages/CADKernel` imports it. The costs are real but acceptable for a CAD app: about 60 MB more on disk (21 MB zipped), a clean build that is roughly 8× slower, a 149 MB download for every new checkout and CI run, and no Intel support. Revisit if OCCTSwift stalls or the binary size becomes a problem. The fallback is our own thin bridge over only the OCCT toolkits we use, which would also cut the size.
