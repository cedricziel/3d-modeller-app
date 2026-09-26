#include "COndselSolver.h"

#include <OndselSolver/ASMTAssembly.h>
#include <OndselSolver/ASMTCylindricalJoint.h>
#include <OndselSolver/ASMTFixedJoint.h>
#include <OndselSolver/ASMTJoint.h>
#include <OndselSolver/ASMTMarker.h>
#include <OndselSolver/ASMTPart.h>
#include <OndselSolver/ASMTPlanarJoint.h>
#include <OndselSolver/ASMTPrincipalMassMarker.h>
#include <OndselSolver/ASMTRevoluteJoint.h>
#include <OndselSolver/ASMTSphericalJoint.h>
#include <OndselSolver/ASMTTranslationalJoint.h>
#include <OndselSolver/CREATE.h>
#include <OndselSolver/Constraint.h>
#include <OndselSolver/FullMatrix.h>
#include <OndselSolver/Joint.h>
#include <OndselSolver/System.h>

#include <cstdio>
#include <iostream>
#include <memory>
#include <mutex>
#include <streambuf>
#include <string>
#include <vector>

using namespace MbD;

namespace {

struct Body {
    OSPlacement placement;
    bool grounded;
};

struct JointSpec {
    int32_t kind;
    int32_t bodyA;
    OSPlacement markerA;
    int32_t bodyB;
    OSPlacement markerB;
};

class NullBuffer : public std::streambuf {
protected:
    int overflow(int character) override { return traits_type::not_eof(character); }
    std::streamsize xsputn(const char*, std::streamsize count) override { return count; }
};

/// OndselSolver logs every iteration to std::cout; nobody should see that.
class MutedStdout {
public:
    MutedStdout() : previous(std::cout.rdbuf(&null)) {}
    ~MutedStdout() { std::cout.rdbuf(previous); }
    MutedStdout(const MutedStdout&) = delete;
    MutedStdout& operator=(const MutedStdout&) = delete;

private:
    NullBuffer null;
    std::streambuf* previous;
};

/// OndselSolver's thread safety is unverified, so solves run one at a time.
std::mutex& solveMutex()
{
    static std::mutex mutex;
    return mutex;
}

}  // namespace

struct OSAssembly {
    std::vector<Body> bodies;
    std::vector<JointSpec> joints;
    std::vector<OSPlacement> solved;
    std::vector<OSJointReport> reports;
    char lastError[256] = {0};

    void fail(const char* message) noexcept { std::snprintf(lastError, sizeof lastError, "%s", message); }
};

namespace {

template<typename F>
int32_t guarded(OSAssembly* assembly, F&& body) noexcept
{
    try {
        return body();
    }
    catch (const std::exception& error) {
        assembly->fail(error.what());
    }
    catch (...) {
        assembly->fail("unknown C++ exception");
    }
    return OS_ERR_EXCEPTION;
}

void place(ASMTSpatialItem& item, const OSPlacement& p)
{
    item.setPosition3D(p.translation[0], p.translation[1], p.translation[2]);
    const double* r = p.rotation;
    item.setRotationMatrix(r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]);
}

std::shared_ptr<ASMTMarker> marker(const std::string& name, const OSPlacement& p)
{
    auto result = CREATE<ASMTMarker>::With();
    result->setName(name);
    place(*result, p);
    return result;
}

std::shared_ptr<ASMTJoint> jointOfKind(int32_t kind)
{
    switch (kind) {
        case OS_FIXED: return CREATE<ASMTFixedJoint>::With();
        case OS_REVOLUTE: return CREATE<ASMTRevoluteJoint>::With();
        case OS_SLIDER: return CREATE<ASMTTranslationalJoint>::With();
        case OS_CYLINDRICAL: return CREATE<ASMTCylindricalJoint>::With();
        case OS_BALL: return CREATE<ASMTSphericalJoint>::With();
        case OS_PLANAR: return CREATE<ASMTPlanarJoint>::With();
        default: return nullptr;
    }
}

const OSPlacement identity = {{1, 0, 0, 0, 1, 0, 0, 0, 1}, {0, 0, 0}};
const std::string root = "/OndselAssembly/";

}  // namespace

extern "C" {

OSAssembly* os_create(void)
{
    try {
        return new OSAssembly();
    }
    catch (...) {
        return nullptr;
    }
}

void os_destroy(OSAssembly* assembly)
{
    delete assembly;
}

int32_t os_add_body(OSAssembly* assembly, OSPlacement placement, int32_t grounded)
{
    return guarded(assembly, [&] {
        assembly->bodies.push_back({placement, grounded != 0});
        return static_cast<int32_t>(assembly->bodies.size() - 1);
    });
}

int32_t os_add_joint(
    OSAssembly* assembly, int32_t kind, int32_t bodyA, OSPlacement markerA, int32_t bodyB, OSPlacement markerB)
{
    return guarded(assembly, [&] {
        const auto count = static_cast<int32_t>(assembly->bodies.size());
        if (kind < OS_FIXED || kind > OS_PLANAR || bodyA < 0 || bodyA >= count || bodyB < 0 || bodyB >= count
            || bodyA == bodyB) {
            assembly->fail("invalid joint");
            return static_cast<int32_t>(OS_ERR_ARGUMENT);
        }
        assembly->joints.push_back({kind, bodyA, markerA, bodyB, markerB});
        return static_cast<int32_t>(assembly->joints.size() - 1);
    });
}

int32_t os_solve(OSAssembly* assembly)
{
    return guarded(assembly, [&] {
        std::lock_guard<std::mutex> lock(solveMutex());
        MutedStdout muted;
        assembly->solved.clear();
        assembly->reports.clear();

        auto mbd = CREATE<ASMTAssembly>::With();
        mbd->setName("OndselAssembly");
        std::vector<std::shared_ptr<ASMTPart>> parts;
        for (std::size_t index = 0; index < assembly->bodies.size(); ++index) {
            const auto& body = assembly->bodies[index];
            const std::string name = "body" + std::to_string(index);
            auto part = CREATE<ASMTPart>::With();
            part->setName(name);
            auto mass = CREATE<ASMTPrincipalMassMarker>::With();
            mass->setMass(1.0);
            mass->setDensity(1.0);
            mass->setMomentOfInertias(1.0, 1.0, 1.0);
            part->setPrincipalMassMarker(mass);
            place(*part, body.placement);
            mbd->addPart(part);
            parts.push_back(part);
            if (body.grounded) {
                const std::string groundName = "ground" + std::to_string(index);
                mbd->addMarker(marker(groundName, body.placement));
                part->addMarker(marker("FixingMarker", identity));
                auto fixing = CREATE<ASMTFixedJoint>::With();
                fixing->setName("grounding" + std::to_string(index));
                fixing->setMarkerI(root + groundName);
                fixing->setMarkerJ(root + name + "/FixingMarker");
                mbd->addJoint(fixing);
            }
        }
        std::vector<std::shared_ptr<ASMTJoint>> joints;
        for (std::size_t index = 0; index < assembly->joints.size(); ++index) {
            const auto& spec = assembly->joints[index];
            const std::string name = "joint" + std::to_string(index);
            parts[spec.bodyA]->addMarker(marker(name + "a", spec.markerA));
            parts[spec.bodyB]->addMarker(marker(name + "b", spec.markerB));
            auto joint = jointOfKind(spec.kind);
            joint->setName(name);
            joint->setMarkerI(root + parts[spec.bodyA]->name + "/" + name + "a");
            joint->setMarkerJ(root + parts[spec.bodyB]->name + "/" + name + "b");
            mbd->addJoint(joint);
            joints.push_back(joint);
        }

        mbd->runPreDrag();

        for (auto& part : parts) {
            OSPlacement result;
            part->getPosition3D(result.translation[0], result.translation[1], result.translation[2]);
            for (std::size_t row = 0; row < 3; ++row) {
                for (std::size_t column = 0; column < 3; ++column) {
                    result.rotation[row * 3 + column] = part->rotationMatrix->at(row)->at(column);
                }
            }
            assembly->solved.push_back(result);
        }
        for (auto& joint : joints) {
            OSJointReport report = {0, 0};
            auto mbdJoint = std::dynamic_pointer_cast<Joint>(joint->mbdObject);
            if (mbdJoint) {
                mbdJoint->constraintsDo([&](std::shared_ptr<Constraint> constraint) {
                    report.constraints += 1;
                    if (constraint && constraint->constraintSpec().rfind("Redundant", 0) == 0) {
                        report.redundant += 1;
                    }
                });
            }
            assembly->reports.push_back(report);
        }
        return static_cast<int32_t>(OS_OK);
    });
}

int32_t os_body_placement(const OSAssembly* assembly, int32_t body, OSPlacement* placement)
{
    if (body < 0 || static_cast<std::size_t>(body) >= assembly->solved.size()) {
        return OS_ERR_ARGUMENT;
    }
    *placement = assembly->solved[static_cast<std::size_t>(body)];
    return OS_OK;
}

int32_t os_joint_report(const OSAssembly* assembly, int32_t joint, OSJointReport* report)
{
    if (joint < 0 || static_cast<std::size_t>(joint) >= assembly->reports.size()) {
        return OS_ERR_ARGUMENT;
    }
    *report = assembly->reports[static_cast<std::size_t>(joint)];
    return OS_OK;
}

const char* os_last_error(const OSAssembly* assembly)
{
    return assembly->lastError;
}

}  // extern "C"
