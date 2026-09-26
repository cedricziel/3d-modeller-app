#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma clang assume_nonnull begin

/// An OndselSolver assembly under construction. Every function catches all C++ exceptions and reports them
/// through its return value and `os_last_error`.
typedef struct OSAssembly OSAssembly;

enum {
    OS_OK = 0,
    OS_ERR_ARGUMENT = -1,
    OS_ERR_EXCEPTION = -2,
};

enum {
    OS_FIXED = 0,
    OS_REVOLUTE = 1,
    OS_SLIDER = 2,
    OS_CYLINDRICAL = 3,
    OS_BALL = 4,
    OS_PLANAR = 5,
};

/// A rotation, row-major, and a translation.
typedef struct {
    double rotation[9];
    double translation[3];
} OSPlacement;

typedef struct {
    int32_t constraints;
    int32_t redundant;
} OSJointReport;

OSAssembly *_Nullable os_create(void);
void os_destroy(OSAssembly *_Nullable assembly);
/// Returns the body index, or a negative error.
int32_t os_add_body(OSAssembly *assembly, OSPlacement placement, int32_t grounded);
/// Markers are in their body's coordinates. Returns the joint index, or a negative error.
int32_t os_add_joint(
    OSAssembly *assembly, int32_t kind, int32_t bodyA, OSPlacement markerA, int32_t bodyB, OSPlacement markerB);
/// Solves the assembly in place (OndselSolver's `runPreDrag`). Returns `OS_OK` or a negative error.
int32_t os_solve(OSAssembly *assembly);
int32_t os_body_placement(const OSAssembly *assembly, int32_t body, OSPlacement *placement);
/// Valid after a successful solve.
int32_t os_joint_report(const OSAssembly *assembly, int32_t joint, OSJointReport *report);
const char *os_last_error(const OSAssembly *assembly);

#pragma clang assume_nonnull end

#ifdef __cplusplus
}
#endif
