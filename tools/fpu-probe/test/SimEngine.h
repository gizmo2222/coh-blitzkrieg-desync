#pragma once
#ifdef SIMENGINE_EXPORTS
#define SIM_API __declspec(dllexport)
#else
#define SIM_API __declspec(dllimport)
#endif

class SIM_API World {
public:
    unsigned short preCw;
    unsigned preMx;
    World* preThis;
    int ticks;
    World() : preCw(0), preMx(0), preThis(0), ticks(0) {}
    virtual void Simulate();  // ?Simulate@World@@UAEXXZ, one call per sim tick
};
