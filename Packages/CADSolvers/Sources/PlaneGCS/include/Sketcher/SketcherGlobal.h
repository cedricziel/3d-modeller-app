#pragma once

// Local shim for FreeCAD's src/Mod/Sketcher/SketcherGlobal.h. PlaneGCS relies on these standard
// headers arriving through FreeCAD's precompiled header.
#include <cassert>
#include <cmath>
#include <iterator>
#include <utility>

#define SketcherExport

// PlaneGCS narrows Eigen and container sizes to int throughout; SwiftPM enables
// -Wshorten-64-to-32 for C++ targets and offers no safe flag to turn it off per target.
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
