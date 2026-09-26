#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma clang assume_nonnull begin

typedef struct PGSSketch PGSSketch;

PGSSketch *_Nullable pgs_create(void);
void pgs_destroy(PGSSketch *_Nullable sketch);

#pragma clang assume_nonnull end

#ifdef __cplusplus
}
#endif
