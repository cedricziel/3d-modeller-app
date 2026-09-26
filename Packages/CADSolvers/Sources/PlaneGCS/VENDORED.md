# Vendored code in the PlaneGCS target

`Scripts/vendor-planegcs.sh` rebuilds everything listed under "Vendored" from the pinned
revisions below. Do not edit vendored files by hand; change the shims or the pins instead.

## Vendored

### PlaneGCS (FreeCAD)

- Source: https://github.com/FreeCAD/FreeCAD, directory `src/Mod/Sketcher/App/planegcs/`
- Commit: `6387346419221615a3ae500b834665301f867095` (main, 2026-09-26)
- Location: `include/Sketcher/App/planegcs/` (all files of the directory, unmodified)
- Licence: LGPL-2.1-or-later (per-file SPDX headers kept); full text in
  `LICENSES/FreeCAD-LGPL-2.1.txt` (FreeCAD's `LICENSE` at the same commit)

### Eigen

- Source: https://gitlab.com/libeigen/eigen, tag `3.4.1`
- Commit: `d71c30c47858effcbd39967097a2d99ee48db464`
- Location: `include/Eigen/`, only the headers that the PlaneGCS sources and
  `Sources/CPlaneGCS/CPlaneGCS.cpp` transitively include on arm64 macOS
  (`clang++ -MM` with the package's defines), in Eigen's own directory layout, unmodified
- Licence: MPL-2.0 (`LICENSES/Eigen-COPYING.MPL2`). A few included files carry other
  permissive licences, kept in their headers: `src/Core/util/MKL_support.h` (BSD,
  `LICENSES/Eigen-COPYING.BSD`) and `src/Core/arch/Default/BFloat16.h` (Apache-2.0,
  `LICENSES/Eigen-COPYING.APACHE`). `LICENSES/Eigen-COPYING.README` is Eigen's licensing note.
  `EIGEN_MPL2_ONLY` is defined, so Eigen refuses to compile any LGPL-only code.

## Local shims (ours, not vendored)

PlaneGCS includes a few FreeCAD and Boost headers from outside its directory. These minimal
replacements stand in for them:

| Shim                                                                                     | Replaces                                    | Why                                                                                                                                                                                                                                             |
| ---------------------------------------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `include/Sketcher/SketcherGlobal.h`                                                      | FreeCAD `src/Mod/Sketcher/SketcherGlobal.h` | Defines `SketcherExport` empty (static library) and includes the standard headers PlaneGCS gets from FreeCAD's precompiled header                                                                                                               |
| `include/Base/Console.h`                                                                 | FreeCAD `Base/Console.h`                    | PlaneGCS only logs diagnostics; the shim drops them                                                                                                                                                                                             |
| `include/Base/Tools.h`, `include/FCConfig.h`                                             | FreeCAD headers                             | Included, nothing used                                                                                                                                                                                                                          |
| `include/boost/math/constants/constants.hpp`, `include/boost/graph/graph_concepts.hpp`   | Boost headers                               | Included, nothing used                                                                                                                                                                                                                          |
| `include/boost_graph_adjacency_list.hpp`, `include/boost/graph/connected_components.hpp` | Boost.Graph                                 | PlaneGCS partitions the system into decoupled components with `adjacency_list`, `add_vertex`, `add_edge`, `num_vertices` and `connected_components`; the shim implements those with a vector adjacency list and an iterative depth-first search |
| `include/module.modulemap`                                                               | —                                           | Keeps Swift from treating the C++ headers as an importable module                                                                                                                                                                               |

## Build settings

`Package.swift` compiles this target as C++23 (`std::unreachable`, `std::numbers`) with
`NDEBUG` and `EIGEN_NO_DEBUG` (as FreeCAD's release builds do), `EIGEN_MPL2_ONLY`, and
`_LIBCPP_DISABLE_DEPRECATION_WARNINGS` (Eigen 3.4 uses `std::float_denorm_style`, deprecated in
C++23). No unsafe flags.

## Updating

1. Change the pinned commit or tag in `Scripts/vendor-planegcs.sh` and in this file.
2. Run `Scripts/vendor-planegcs.sh` from the package directory.
3. Build; if PlaneGCS includes something new from FreeCAD or Boost, extend the shims.
4. Run `xcrun swift test` in `Packages/CADSolvers`.
