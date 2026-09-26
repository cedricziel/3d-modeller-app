#include "CPlaneGCS.h"

#include <algorithm>
#include <cmath>
#include <deque>
#include <exception>
#include <new>
#include <numbers>
#include <string>
#include <vector>

#include <Sketcher/App/planegcs/GCS.h>

namespace
{
enum class Kind
{
    point,
    line,
    circle,
    arc,
};

struct Entity
{
    Kind kind;
    std::size_t index;
};

struct ArgumentError
{
    std::string message;
};

}  // namespace

struct PGSSketch
{
    GCS::System system;
    std::deque<double> storage;
    std::vector<double*> unknowns;
    std::deque<GCS::Point> points;
    std::deque<GCS::Line> lines;
    std::deque<GCS::Circle> circles;
    std::deque<GCS::Arc> arcs;
    std::vector<Entity> entities;
    std::vector<int> conflicting;
    std::vector<int> redundant;
    int highestTag = 0;
    std::string lastError;

    double* unknown(double value)
    {
        storage.push_back(value);
        unknowns.push_back(&storage.back());
        return &storage.back();
    }

    double* constant(double value)
    {
        storage.push_back(value);
        return &storage.back();
    }

    GCS::Point point(double x, double y)
    {
        return GCS::Point(unknown(x), unknown(y));
    }

    const Entity& entity(int32_t index, std::initializer_list<Kind> kinds) const
    {
        if (index < 0 || static_cast<std::size_t>(index) >= entities.size()) {
            throw ArgumentError {"entity index out of range"};
        }
        const Entity& found = entities[static_cast<std::size_t>(index)];
        if (std::find(kinds.begin(), kinds.end(), found.kind) == kinds.end()) {
            throw ArgumentError {"entity has the wrong kind for this constraint"};
        }
        return found;
    }

    GCS::Line& line(int32_t index)
    {
        return lines[entity(index, {Kind::line}).index];
    }

    GCS::Circle& circle(int32_t index)
    {
        const Entity& found = entity(index, {Kind::circle, Kind::arc});
        if (found.kind == Kind::arc) {
            return arcs[found.index];
        }
        return circles[found.index];
    }

    GCS::Curve& curve(int32_t index)
    {
        const Entity& found = entity(index, {Kind::line, Kind::arc});
        if (found.kind == Kind::arc) {
            return arcs[found.index];
        }
        return lines[found.index];
    }

    GCS::Point& point(PGSPointRef ref)
    {
        switch (ref.role) {
            case PGS_ROLE_POINT:
                return points[entity(ref.entity, {Kind::point}).index];
            case PGS_ROLE_START: {
                const Entity& found = entity(ref.entity, {Kind::line, Kind::arc});
                return found.kind == Kind::line ? lines[found.index].p1 : arcs[found.index].start;
            }
            case PGS_ROLE_END: {
                const Entity& found = entity(ref.entity, {Kind::line, Kind::arc});
                return found.kind == Kind::line ? lines[found.index].p2 : arcs[found.index].end;
            }
            case PGS_ROLE_CENTER: {
                const Entity& found = entity(ref.entity, {Kind::circle, Kind::arc});
                return found.kind == Kind::circle ? circles[found.index].center : arcs[found.index].center;
            }
            default:
                throw ArgumentError {"unknown point role"};
        }
    }

    bool isLine(int32_t index) const
    {
        return entity(index, {Kind::line, Kind::circle, Kind::arc}).kind == Kind::line;
    }

    int32_t add(Kind kind, std::size_t index)
    {
        entities.push_back({kind, index});
        return static_cast<int32_t>(entities.size() - 1);
    }
};

namespace
{
template<typename Body>
int32_t guarded(const PGSSketch* sketch, Body&& body) noexcept
{
    auto* mutableSketch = const_cast<PGSSketch*>(sketch);
    try {
        return body();
    }
    catch (const ArgumentError& error) {
        mutableSketch->lastError = error.message;
        return PGS_ERR_ARGUMENT;
    }
    catch (const std::exception& error) {
        mutableSketch->lastError = error.what();
    }
    catch (...) {
        mutableSketch->lastError = "unknown C++ exception";
    }
    return PGS_ERR_EXCEPTION;
}

/// Positive when the point lies counter-clockwise from the line's direction, as FreeCAD's
/// Sketch::signedDistanceToLine decides which side a tangent circle keeps.
double signedDistance(const GCS::Line& line, double x, double y)
{
    const double dx = *line.p2.x - *line.p1.x;
    const double dy = *line.p2.y - *line.p1.y;
    const double length = std::hypot(dx, dy);
    if (length == 0) {
        return 0;
    }
    return (dx * (y - *line.p1.y) - dy * (x - *line.p1.x)) / length;
}

/// 0 or π, whichever the current tangent directions are closer to (FreeCAD's autodetection for
/// endpoint-to-endpoint tangency).
double tangentAngle(GCS::System& system, GCS::Curve& first, GCS::Curve& second, GCS::Point& at)
{
    using std::numbers::pi;
    double error = system.calculateAngleViaPoint(first, second, at);
    error = std::remainder(error, 2 * pi);
    return std::fabs(error) > pi / 2 ? pi : 0;
}

void addConstraint(PGSSketch& sketch, int tag, const PGSConstraint& c)
{
    GCS::System& system = sketch.system;
    switch (c.kind) {
        case PGS_COINCIDENT:
            system.addConstraintP2PCoincident(sketch.point(c.p1), sketch.point(c.p2), tag);
            return;
        case PGS_HORIZONTAL:
            system.addConstraintHorizontal(sketch.line(c.first), tag);
            return;
        case PGS_VERTICAL:
            system.addConstraintVertical(sketch.line(c.first), tag);
            return;
        case PGS_PARALLEL:
            system.addConstraintParallel(sketch.line(c.first), sketch.line(c.second), tag);
            return;
        case PGS_PERPENDICULAR:
            system.addConstraintPerpendicular(sketch.line(c.first), sketch.line(c.second), tag);
            return;
        case PGS_TANGENT: {
            int32_t first = c.first;
            int32_t second = c.second;
            if (sketch.isLine(second)) {
                std::swap(first, second);
            }
            if (sketch.isLine(first)) {
                GCS::Line& line = sketch.line(first);
                GCS::Circle& circle = sketch.circle(second);
                const bool ccw = signedDistance(line, *circle.center.x, *circle.center.y) > 0;
                system.addConstraintTangent(line, circle, ccw, tag);
            }
            else {
                system.addConstraintTangent(sketch.circle(first), sketch.circle(second), tag);
            }
            return;
        }
        case PGS_TANGENT_AT: {
            GCS::Point& at = sketch.point(c.p1);
            GCS::Point& other = sketch.point(c.p2);
            GCS::Curve& first = sketch.curve(c.p1.entity);
            GCS::Curve& second = sketch.curve(c.p2.entity);
            double* angle = sketch.constant(tangentAngle(system, first, second, at));
            system.addConstraintP2PCoincident(at, other, tag);
            system.addConstraintAngleViaPoint(first, second, at, angle, tag);
            return;
        }
        case PGS_EQUAL:
            if (sketch.isLine(c.first)) {
                system.addConstraintEqualLength(sketch.line(c.first), sketch.line(c.second), tag);
            }
            else {
                system.addConstraintEqualRadius(sketch.circle(c.first), sketch.circle(c.second), tag);
            }
            return;
        case PGS_DISTANCE:
            system.addConstraintP2PDistance(sketch.point(c.p1), sketch.point(c.p2), sketch.constant(c.value), tag);
            return;
        case PGS_POINT_LINE_DISTANCE: {
            GCS::Point& point = sketch.point(c.p1);
            GCS::Line& line = sketch.line(c.first);
            const bool ccw = signedDistance(line, *point.x, *point.y) > 0;
            system.addConstraintP2LDistance(point, line, sketch.constant(c.value), ccw, tag);
            return;
        }
        case PGS_ANGLE:
            system.addConstraintL2LAngle(sketch.line(c.first), sketch.line(c.second), sketch.constant(c.value), tag);
            return;
        case PGS_RADIUS:
            system.addConstraintCircleRadius(sketch.circle(c.first), sketch.constant(c.value), tag);
            return;
        case PGS_DIAMETER:
            system.addConstraintCircleDiameter(sketch.circle(c.first), sketch.constant(c.value), tag);
            return;
        case PGS_FIXED: {
            GCS::Point& point = sketch.point(c.p1);
            system.addConstraintCoordinateX(point, sketch.constant(*point.x), tag);
            system.addConstraintCoordinateY(point, sketch.constant(*point.y), tag);
            return;
        }
        case PGS_POINT_ON_LINE:
            system.addConstraintPointOnLine(sketch.point(c.p1), sketch.line(c.first), tag);
            return;
        case PGS_POINT_ON_CIRCLE:
            system.addConstraintPointOnCircle(sketch.point(c.p1), sketch.circle(c.first), tag);
            return;
        default:
            throw ArgumentError {"unknown constraint kind"};
    }
}

void keepPositiveTags(std::vector<int>& tags)
{
    std::erase_if(tags, [](int tag) { return tag <= 0; });
    std::sort(tags.begin(), tags.end());
    tags.erase(std::unique(tags.begin(), tags.end()), tags.end());
}

void readDiagnosis(PGSSketch& sketch, PGSReport& report)
{
    sketch.system.getConflicting(sketch.conflicting);
    sketch.system.getRedundant(sketch.redundant);
    keepPositiveTags(sketch.conflicting);
    keepPositiveTags(sketch.redundant);
    report.dof = sketch.system.dofsNumber();
    report.conflictingCount = static_cast<int32_t>(sketch.conflicting.size());
    report.redundantCount = static_cast<int32_t>(sketch.redundant.size());
}

/// PlaneGCS checks redundant constraints against the parameters before it writes the solution
/// back, so a sketch with a redundant constraint solved from a rough start reports `Converged`
/// although it is solved. Every constraint is therefore checked on the applied solution instead.
bool satisfiesEveryConstraint(PGSSketch& sketch)
{
    const int firstTag = sketch.arcs.empty() ? 1 : 0;
    for (int tag = firstTag; tag <= sketch.highestTag; ++tag) {
        const double error = sketch.system.calculateConstraintErrorByTag(tag);
        if (!(error * error <= sketch.system.convergence)) {
            return false;
        }
    }
    return true;
}

int32_t copyTags(const std::vector<int>& source, int32_t* tags, int32_t capacity)
{
    const auto count = std::min<std::size_t>(source.size(), static_cast<std::size_t>(std::max(capacity, 0)));
    std::copy_n(source.begin(), count, tags);
    return static_cast<int32_t>(count);
}
}  // namespace

extern "C" {

PGSSketch* pgs_create(void)
{
    try {
        auto* sketch = new PGSSketch();
        sketch->system.debugMode = GCS::NoDebug;
        return sketch;
    }
    catch (...) {
        return nullptr;
    }
}

void pgs_destroy(PGSSketch* sketch)
{
    delete sketch;
}

int32_t pgs_add_point(PGSSketch* sketch, double x, double y)
{
    return guarded(sketch, [&] {
        sketch->points.push_back(sketch->point(x, y));
        return sketch->add(Kind::point, sketch->points.size() - 1);
    });
}

int32_t pgs_add_line(PGSSketch* sketch, double x1, double y1, double x2, double y2)
{
    return guarded(sketch, [&] {
        GCS::Line line;
        line.p1 = sketch->point(x1, y1);
        line.p2 = sketch->point(x2, y2);
        sketch->lines.push_back(line);
        return sketch->add(Kind::line, sketch->lines.size() - 1);
    });
}

int32_t pgs_add_circle(PGSSketch* sketch, double cx, double cy, double radius)
{
    return guarded(sketch, [&] {
        GCS::Circle circle;
        circle.center = sketch->point(cx, cy);
        circle.rad = sketch->unknown(radius);
        sketch->circles.push_back(circle);
        return sketch->add(Kind::circle, sketch->circles.size() - 1);
    });
}

int32_t pgs_add_arc(PGSSketch* sketch, double cx, double cy, double radius, double startAngle, double endAngle)
{
    return guarded(sketch, [&] {
        GCS::Arc arc;
        arc.center = sketch->point(cx, cy);
        arc.rad = sketch->unknown(radius);
        arc.startAngle = sketch->unknown(startAngle);
        arc.endAngle = sketch->unknown(endAngle);
        arc.start = sketch->point(cx + radius * std::cos(startAngle), cy + radius * std::sin(startAngle));
        arc.end = sketch->point(cx + radius * std::cos(endAngle), cy + radius * std::sin(endAngle));
        sketch->arcs.push_back(arc);
        sketch->system.addConstraintArcRules(sketch->arcs.back());
        return sketch->add(Kind::arc, sketch->arcs.size() - 1);
    });
}

int32_t pgs_add_constraint(PGSSketch* sketch, int32_t tag, PGSConstraint constraint)
{
    return guarded(sketch, [&] {
        if (tag <= 0) {
            throw ArgumentError {"constraint tags must be greater than 0"};
        }
        addConstraint(*sketch, tag, constraint);
        sketch->highestTag = std::max(sketch->highestTag, int(tag));
        return int32_t {PGS_OK};
    });
}

int32_t pgs_solve(PGSSketch* sketch, PGSReport* report)
{
    return guarded(sketch, [&] {
        *report = PGSReport {};
        GCS::System& system = sketch->system;
        system.declareUnknowns(sketch->unknowns);
        system.initSolution(GCS::DogLeg);

        bool solved = false;
        for (GCS::Algorithm algorithm : {GCS::DogLeg, GCS::LevenbergMarquardt, GCS::BFGS}) {
            if (system.solve(algorithm) == GCS::SolveStatus::Failed) {
                continue;
            }
            system.applySolution();
            if (satisfiesEveryConstraint(*sketch)) {
                solved = true;
                break;
            }
        }

        if (solved) {
            system.invalidatedDiagnosis();
            system.initSolution(GCS::DogLeg);
            report->solved = 1;
        }
        else {
            system.undoSolution();
        }
        readDiagnosis(*sketch, *report);
        return int32_t {PGS_OK};
    });
}

int32_t pgs_conflicting(const PGSSketch* sketch, int32_t* tags, int32_t capacity)
{
    return copyTags(sketch->conflicting, tags, capacity);
}

int32_t pgs_redundant(const PGSSketch* sketch, int32_t* tags, int32_t capacity)
{
    return copyTags(sketch->redundant, tags, capacity);
}

int32_t pgs_entity_values(const PGSSketch* sketch, int32_t entity, double* values, int32_t capacity)
{
    return guarded(sketch, [&] {
        const Entity& found = sketch->entity(entity, {Kind::point, Kind::line, Kind::circle, Kind::arc});
        std::vector<double> out;
        switch (found.kind) {
            case Kind::point: {
                const GCS::Point& p = sketch->points[found.index];
                out = {*p.x, *p.y};
                break;
            }
            case Kind::line: {
                const GCS::Line& l = sketch->lines[found.index];
                out = {*l.p1.x, *l.p1.y, *l.p2.x, *l.p2.y};
                break;
            }
            case Kind::circle: {
                const GCS::Circle& c = sketch->circles[found.index];
                out = {*c.center.x, *c.center.y, *c.rad};
                break;
            }
            case Kind::arc: {
                const GCS::Arc& a = sketch->arcs[found.index];
                out = {*a.center.x, *a.center.y, *a.rad, *a.startAngle, *a.endAngle};
                break;
            }
        }
        if (capacity < static_cast<int32_t>(out.size())) {
            throw ArgumentError {"value buffer too small"};
        }
        std::copy(out.begin(), out.end(), values);
        return static_cast<int32_t>(out.size());
    });
}

const char* pgs_last_error(const PGSSketch* sketch)
{
    return sketch->lastError.c_str();
}
}
