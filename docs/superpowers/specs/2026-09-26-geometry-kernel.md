# Geometry kernel decision

Date: 2026-09-26. Status: accepted for a spike.

## Context

The app is heading toward real parametric CAD: sketches, extrusions, fillets, booleans, STEP exchange. RealityKit only renders triangle meshes, and the current primitives are RealityKit meshes with no exact geometry behind them. We need a B-rep geometry kernel.

The project is open source under Apache-2.0.

## Decision

- **Kernel:** Open CASCADE Technology (OCCT) 8.0.1.
- **Swift access:** OCCTSwift (`SecondMouseAU/OCCTSwift`), pinned to an exact release (`3.0.0`), used only from a local package `Packages/CADKernel`. No other target imports OCCTSwift.
- **CADKernel's surface** is our own small vocabulary (extrude, fillet, tessellate, measure, later sketch/boolean/export). If OCCTSwift stalls we replace what sits behind that surface without touching the app.
- **Rendering:** CADKernel returns plain triangle data; the app turns it into a RealityKit `MeshResource`.
- **Sketch solver (later):** CadQuery/PlaneGCS (LGPL-2.1). ezpz (MIT, Rust) is the fallback.
- **File format (later):** the native document becomes a feature tree (ordered, named, parameterised steps). STEP for exchange; STL/3MF and USDZ/glTF as exports.

## Why

- OCCT is the only free kernel with exact geometry, dependable fillets and real STEP. Truck (Rust) has single-edge fillets only, unreleased. Manifold and SDF kernels have no exact edges. Fornjot shut down in June 2026. CGAL and SolveSpace are GPL. Zoo's kernel is cloud-only. Parasolid/C3D licences don't allow redistribution in an open-source project.
- Swift cannot use OCCT directly: no support for OCCT's `Handle<>` or class templates, and Swift cannot catch C++ exceptions, so a failed fillet would crash the app. A C/Objective-C++ bridge is required; OCCTSwift is one, with a prebuilt `OCCT.xcframework`, so contributors don't have to build OCCT.

## Licensing

- OCCT: LGPL-2.1 + Open CASCADE Exception 1.0. OCCTSwift: LGPL-2.1, ships the same exception.
- Because the whole app is published under Apache-2.0, users can rebuild it against a modified library, which satisfies LGPL's relinking requirement even with static linking.
- The exception requires a prominent notice that the software uses OCCT: add a `NOTICE` file and a README acknowledgement.
- GPL components (SolveSpace libslvs, CGAL) stay out: they would force the app to GPLv3 and conflict with Mac App Store terms.

## Known risks

- OCCTSwift: one maintainer, ~282 open issues, three major versions in six weeks (v4 in beta). Mitigated by pinning and by the CADKernel boundary.
- OCCTSwift serialises OCCT calls through a global recursive lock (`OCCTSerial.withLock`).
- The prebuilt xcframework is 142 MB zipped, ~1.3 GB unpacked, for every contributor and CI run. Shipped app size is unknown until measured.
- OCCT fillets and booleans fail on awkward geometry; every kernel call must return a typed error, never crash.
- CAD is Z-up; RealityKit is Y-up.

## Open questions the spike must answer

1. Release app size before and after adding the kernel.
2. Clean build time and incremental build time with OCCTSwift.
3. Does the Swift 6 / macOS 26 toolchain build OCCTSwift 3.0.0 cleanly?
4. Does the tessellated mesh render correctly in RealityKit (winding, normals, orientation)?
