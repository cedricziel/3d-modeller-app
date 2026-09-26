#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma clang assume_nonnull begin

/// A PlaneGCS system under construction. Every function catches all C++ exceptions and reports
/// them through its return value and `pgs_last_error`.
typedef struct PGSSketch PGSSketch;

enum {
    PGS_OK = 0,
    PGS_ERR_ARGUMENT = -1,
    PGS_ERR_EXCEPTION = -2,
};

enum {
    PGS_ROLE_POINT = 0,
    PGS_ROLE_START = 1,
    PGS_ROLE_END = 2,
    PGS_ROLE_CENTER = 3,
};

enum {
    PGS_COINCIDENT = 0,
    PGS_HORIZONTAL = 1,
    PGS_VERTICAL = 2,
    PGS_PARALLEL = 3,
    PGS_PERPENDICULAR = 4,
    PGS_TANGENT = 5,
    PGS_TANGENT_AT = 6,
    PGS_EQUAL = 7,
    PGS_DISTANCE = 8,
    PGS_POINT_LINE_DISTANCE = 9,
    PGS_ANGLE = 10,
    PGS_RADIUS = 11,
    PGS_DIAMETER = 12,
    PGS_FIXED = 13,
    PGS_POINT_ON_LINE = 14,
    PGS_POINT_ON_CIRCLE = 15,
};

typedef struct {
    int32_t entity;
    int32_t role;
} PGSPointRef;

/// `first`/`second` are entity indices, `p1`/`p2` point references; which fields a kind reads
/// follows the Swift `SketchConstraint` case of the same name.
typedef struct {
    int32_t kind;
    int32_t first;
    int32_t second;
    PGSPointRef p1;
    PGSPointRef p2;
    double value;
} PGSConstraint;

typedef struct {
    int32_t solved;
    int32_t dof;
    int32_t conflictingCount;
    int32_t redundantCount;
} PGSReport;

PGSSketch *_Nullable pgs_create(void);
void pgs_destroy(PGSSketch *_Nullable sketch);

/// Each returns the new entity's index, or a negative error.
int32_t pgs_add_point(PGSSketch *sketch, double x, double y);
int32_t pgs_add_line(PGSSketch *sketch, double x1, double y1, double x2, double y2);
int32_t pgs_add_circle(PGSSketch *sketch, double cx, double cy, double radius);
int32_t pgs_add_arc(PGSSketch *sketch, double cx, double cy, double radius, double startAngle, double endAngle);

/// `tag` must be greater than 0; diagnosis reports constraints by tag.
int32_t pgs_add_constraint(PGSSketch *sketch, int32_t tag, PGSConstraint constraint);

int32_t pgs_solve(PGSSketch *sketch, PGSReport *report);

/// Copy up to `capacity` tags and return how many were copied.
int32_t pgs_conflicting(const PGSSketch *sketch, int32_t *tags, int32_t capacity);
int32_t pgs_redundant(const PGSSketch *sketch, int32_t *tags, int32_t capacity);

/// Point: x y. Line: x1 y1 x2 y2. Circle: cx cy r. Arc: cx cy r start end. Returns the count
/// written, or a negative error.
int32_t pgs_entity_values(const PGSSketch *sketch, int32_t entity, double *values, int32_t capacity);

const char *pgs_last_error(const PGSSketch *sketch);

#pragma clang assume_nonnull end

#ifdef __cplusplus
}
#endif
