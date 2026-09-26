#pragma once

// Local shim for FreeCAD's Base/Console.h: PlaneGCS only logs diagnostics, which are dropped.
namespace Base
{
struct ConsoleSingleton
{
    template<typename... Args>
    void log(Args&&...)
    {}
    template<typename... Args>
    void warning(Args&&...)
    {}
    template<typename... Args>
    void error(Args&&...)
    {}
};

inline ConsoleSingleton& Console()
{
    static ConsoleSingleton console;
    return console;
}
}  // namespace Base
