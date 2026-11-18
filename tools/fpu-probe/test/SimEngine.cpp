// Stand-in for the game's SimEngine.dll: exports a virtual World::Simulate under the same
// decorated name, starting with the same five bytes, so the probe's detour can be tested in
// probe-test.exe.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define SIMENGINE_EXPORTS
#include "SimEngine.h"

// The work of one tick: record what the tick started with, then change the x87 setting.
static void __stdcall TickBody(World* w) {
    unsigned short c;
    unsigned m;
    __asm fnstcw c
    __asm stmxcsr m
    w->preCw = c;
    w->preMx = m;
    w->preThis = w;
    ++w->ticks;
    unsigned short pc64 = 0x037F;  // something changes the setting during the tick
    __asm fldcw pc64
}

// Same first bytes as the real one: push ecx; push ebx; push esi; mov esi,ecx.
__declspec(naked) void World::Simulate() {
    __asm {
        _emit 0x51
        _emit 0x53
        _emit 0x56
        _emit 0x8B
        _emit 0xF1
        push esi
        call TickBody
        pop esi
        pop ebx
        pop ecx
        ret
    }
}
