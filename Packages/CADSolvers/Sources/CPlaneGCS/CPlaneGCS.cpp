#include "CPlaneGCS.h"

#include <new>

#include <Sketcher/App/planegcs/GCS.h>

struct PGSSketch
{
    GCS::System system;
};

extern "C" PGSSketch* pgs_create(void)
{
    return new (std::nothrow) PGSSketch();
}

extern "C" void pgs_destroy(PGSSketch* sketch)
{
    delete sketch;
}
