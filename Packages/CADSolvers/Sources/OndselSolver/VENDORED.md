# Vendored code in the OndselSolver target

`Scripts/vendor-ondselsolver.sh` rebuilds everything under `include/OndselSolver/` and
`LICENSES/` from the pinned revision below. Do not edit vendored files by hand. Change the
wrapper or the pin instead.

## Vendored

- Source: https://github.com/FreeCAD/OndselSolver, directory `OndselSolver/`. The earlier
  Ondsel-Development repository is archived; FreeCAD maintains the solver now.
- Commit: `4be80eef02a3486cda0d78f3ccbb308d207a9639` (main, 2026-09-19)
- Location: `include/OndselSolver/`, unmodified. It holds the files that upstream's
  `OndselSolver/CMakeLists.txt` lists in `ONDSELSOLVER_SRC` and `ONDSELSOLVER_HEADERS`, plus
  every other header of the directory, because some listed sources include headers the list
  leaves out.
- Not vendored: the sources outside the CMake list (`ASMTAtPointJoint.cpp`,
  `ASMTInLineJoint.cpp`, `Functions.cpp`, `StepFunction.cpp`, `Transitions.cpp`), the sample
  `.asmt`/`.mbd`/`.mov` files, and the Visual Studio project files.
- Licence: LGPL-2.1 (`LICENSES/OndselSolver-LGPL-2.1.txt`, upstream's `LICENSE` at the same
  commit).

## Local files (ours, not vendored)

| File                      | Why |
| ------------------------- | --- |
| `NarrowingWrappers.cpp`   | Five upstream files (`AbsConstraint.cpp`, `AtPointConstraintIqcJqc.cpp`, `DirectionCosineConstraintIqcJqc.cpp`, `TranslationConstraintIqcJqc.cpp`, `SymbolicParser.cpp`) narrow `size_t` to `int`. That trips `-Wshorten-64-to-32`, which SwiftPM enables. `Package.swift` excludes them from the target, and this file includes them under a pragma that silences only that warning. |
| `include/module.modulemap` | Keeps Swift from treating the C++ headers as an importable module. |

## Build settings

`Package.swift` compiles the target as C++23 with `NDEBUG`, as a release build of FreeCAD
does. It uses no unsafe flags. The solver prints progress to `std::cout`, and the
`COndselSolver` shim mutes it during a solve.

## Updating

1. Change the pinned commit in `Scripts/vendor-ondselsolver.sh` and in this file.
2. Run `Scripts/vendor-ondselsolver.sh` from the package directory.
3. Build. If a new file warns, add it to `NarrowingWrappers.cpp` and to `ondselWrapped` in
   `Package.swift`.
4. Run `xcrun swift test` in `Packages/CADSolvers`.
