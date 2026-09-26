#pragma once

// Local shim for FreeCAD's src/Mod/Sketcher/SketcherGlobal.h. PlaneGCS relies on these standard
// headers arriving through FreeCAD's precompiled header.
#include <cassert>
#include <cmath>
#include <iterator>
#include <utility>

#define SketcherExport
