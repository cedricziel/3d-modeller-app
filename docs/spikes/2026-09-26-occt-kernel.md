# OCCT kernel spike: findings

Spec: `docs/superpowers/specs/2026-09-26-geometry-kernel.md`

## Size and build time (Release, arm64, CODE_SIGNING_ALLOWED=NO)

| | Baseline | With CADKernel |
|---|---|---|
| App bundle (`du -sk`, KB) | 3060 | |
| Executable (bytes) | 3122904 | |
| Clean build (s) | 24.9 | |
| Incremental build after touching one app file (s) | | |

## Notes

- First `xcrun swift test` in `Packages/CADKernel` (after the 149 MB `OCCT.xcframework.zip` download, ~18 s): 40 s wall, mostly compiling OCCTSwift's Objective-C++ bridge. The unpacked xcframework takes 594 MB in `.build/artifacts`.
- Swift 6 / macOS 26 SDK builds OCCTSwift 3.0.0 with no warnings in our package.
- OCCTSwift 3.0.0's `Mesh.normals` is a placeholder: OCCT's triangulation has no normals unless computed, and the bridge fills in `(0, 0, 1)` for every vertex. Triangle winding is correct (the bridge flips reversed faces). `CADKernel` computes area-weighted vertex normals itself. Worth reporting upstream.
