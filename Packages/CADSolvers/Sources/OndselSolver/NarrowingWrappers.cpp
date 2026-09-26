// OndselSolver narrows size_t to int in these files. They compile here instead of directly, so the one warning is
// silenced without modifying vendored code or using unsafe flags.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#include "OndselSolver/AbsConstraint.cpp"
#include "OndselSolver/AtPointConstraintIqcJqc.cpp"
#include "OndselSolver/DirectionCosineConstraintIqcJqc.cpp"
#include "OndselSolver/TranslationConstraintIqcJqc.cpp"
#include "OndselSolver/SymbolicParser.cpp"
#pragma clang diagnostic pop
