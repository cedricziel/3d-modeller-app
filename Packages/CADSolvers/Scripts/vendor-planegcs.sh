#!/usr/bin/env bash
# Rebuilds the vendored PlaneGCS sources and the Eigen header subset in Sources/PlaneGCS.
# Usage: Scripts/vendor-planegcs.sh [planegcs|eigen|all]   (default: all)
set -euo pipefail

FREECAD_URL=https://github.com/FreeCAD/FreeCAD.git
FREECAD_COMMIT=6387346419221615a3ae500b834665301f867095
EIGEN_URL=https://gitlab.com/libeigen/eigen.git
EIGEN_TAG=3.4.1
EIGEN_COMMIT=d71c30c47858effcbd39967097a2d99ee48db464

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$PACKAGE_DIR/Sources/PlaneGCS"
INCLUDE_DIR="$TARGET_DIR/include"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
WHAT="${1:-all}"

vendor_planegcs() {
    git clone --quiet --filter=blob:none --no-checkout "$FREECAD_URL" "$WORK_DIR/freecad"
    git -C "$WORK_DIR/freecad" sparse-checkout set --no-cone /LICENSE /src/Mod/Sketcher/App/planegcs/
    git -C "$WORK_DIR/freecad" checkout --quiet "$FREECAD_COMMIT"
    rm -rf "$INCLUDE_DIR/Sketcher/App/planegcs"
    mkdir -p "$INCLUDE_DIR/Sketcher/App" "$TARGET_DIR/LICENSES"
    cp -R "$WORK_DIR/freecad/src/Mod/Sketcher/App/planegcs" "$INCLUDE_DIR/Sketcher/App/planegcs"
    cp "$WORK_DIR/freecad/LICENSE" "$TARGET_DIR/LICENSES/FreeCAD-LGPL-2.1.txt"
}

vendor_eigen() {
    git clone --quiet --depth 1 --branch "$EIGEN_TAG" "$EIGEN_URL" "$WORK_DIR/eigen"
    test "$(git -C "$WORK_DIR/eigen" rev-parse HEAD)" = "$EIGEN_COMMIT"
    rm -rf "$INCLUDE_DIR/Eigen"
    local sources=("$INCLUDE_DIR"/Sketcher/App/planegcs/*.cpp)
    if [ -f "$PACKAGE_DIR/Sources/CPlaneGCS/CPlaneGCS.cpp" ]; then
        sources+=("$PACKAGE_DIR/Sources/CPlaneGCS/CPlaneGCS.cpp")
    fi
    local deps
    deps="$(for source in "${sources[@]}"; do
        xcrun clang++ -std=c++2b -MM \
            -DNDEBUG -DEIGEN_NO_DEBUG -DEIGEN_MPL2_ONLY -D_LIBCPP_DISABLE_DEPRECATION_WARNINGS \
            -I "$WORK_DIR/eigen" -I "$INCLUDE_DIR" -I "$PACKAGE_DIR/Sources/CPlaneGCS/include" "$source"
    done | tr ' \\' '\n\n' | grep "^$WORK_DIR/eigen/" | sort -u)"
    python3 - "$WORK_DIR/eigen" "$INCLUDE_DIR" $deps <<'PY'
import os, shutil, sys
root, dest, files = sys.argv[1], sys.argv[2], sys.argv[3:]
for path in sorted({os.path.normpath(f) for f in files}):
    relative = os.path.relpath(path, root)
    target = os.path.join(dest, relative)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copy2(path, target)
PY
    for license in COPYING.MPL2 COPYING.BSD COPYING.APACHE COPYING.README; do
        cp "$WORK_DIR/eigen/$license" "$TARGET_DIR/LICENSES/Eigen-$license"
    done
}

case "$WHAT" in
    planegcs) vendor_planegcs ;;
    eigen) vendor_eigen ;;
    all) vendor_planegcs; vendor_eigen ;;
    *) echo "usage: $0 [planegcs|eigen|all]" >&2; exit 64 ;;
esac
