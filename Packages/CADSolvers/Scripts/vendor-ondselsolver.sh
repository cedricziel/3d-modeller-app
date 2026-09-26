#!/usr/bin/env bash
# Rebuilds the vendored OndselSolver sources in Sources/OndselSolver from the pinned commit.
# Usage: Scripts/vendor-ondselsolver.sh
set -euo pipefail

ONDSEL_URL=https://github.com/FreeCAD/OndselSolver.git
ONDSEL_COMMIT=4be80eef02a3486cda0d78f3ccbb308d207a9639

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$PACKAGE_DIR/Sources/OndselSolver"
DEST="$TARGET_DIR/include/OndselSolver"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

git clone --quiet --filter=blob:none --no-checkout "$ONDSEL_URL" "$WORK_DIR/ondsel"
git -C "$WORK_DIR/ondsel" -c advice.detachedHead=false checkout --quiet "$ONDSEL_COMMIT"
SOURCE="$WORK_DIR/ondsel/OndselSolver"

rm -rf "$DEST"
mkdir -p "$DEST" "$TARGET_DIR/LICENSES"
listed="$(sed -n '/set(ONDSELSOLVER_SRC/,/^)/p;/set(ONDSELSOLVER_HEADERS/,/^)/p' "$SOURCE/CMakeLists.txt" \
    | grep -o '[A-Za-z0-9_]*\.\(cpp\|h\)' | sort -u)"
for file in $listed; do
    cp "$SOURCE/$file" "$DEST/$file"
done
cp "$SOURCE"/*.h "$DEST/"
cp "$WORK_DIR/ondsel/LICENSE" "$TARGET_DIR/LICENSES/OndselSolver-LGPL-2.1.txt"
