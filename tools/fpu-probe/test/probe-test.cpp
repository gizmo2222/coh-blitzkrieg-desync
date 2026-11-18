// Test host for fpu-probe. Run it with version.dll (the probe) in the same folder and
// FPU_PROBE_FORCE=1, FPU_PROBE_LOGDIR=<empty dir>, FPU_PROBE_NOBOX=1, FPU_PROBE_INTERVAL=1000.
// Checks: forwarding works, threads with odd FPU settings show up, a mid-run change is flagged
// CHANGED, a mismatch line in a new warnings.*.txt triggers the ALERT, and the pin hook on the
// test SimEngine.dll sets cw=007F mx=1F80 before and after each World::Simulate.
// Usage: probe-test <logdir> [nopin]   (nopin: expect the hook to be off, skip the other tests)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <float.h>
#include <stdio.h>
#include <xmmintrin.h>
#include "SimEngine.h"
#pragma comment(lib, "version.lib")

static World g_world;
static unsigned short g_afterCw;
static DWORD WINAPI SimTicks(LPVOID) {
    unsigned c;
    _controlfp_s(&c, _PC_53, _MCW_PC);    // 027F, not the pinned value
    _mm_setcsr(_mm_getcsr() | 0x8040);    // ftz,daz, not the pinned value
    World* volatile w = &g_world;         // call through the vtable, as the game does
    for (int i = 0; i < 5; ++i) {
        if (i == 4) Sleep(1100);          // a stalled tick, for the timing check
        w->Simulate();
    }
    unsigned short cw;
    __asm fnstcw cw
    g_afterCw = cw;
    return 0;
}

// Runs five fake ticks on a fresh thread and checks what the tick saw and left behind.
static bool CheckPin(bool expectPin) {
    HANDLE t = CreateThread(NULL, 0, SimTicks, NULL, 0, NULL);
    WaitForSingleObject(t, 5000);
    CloseHandle(t);
    World& w = g_world;
    printf("World::Simulate ran %d times, last saw cw=%04X mx=%04X, left cw=%04X\n", w.ticks, w.preCw,
           w.preMx, g_afterCw);
    bool thisOk = w.preThis == &w && w.ticks == 5;
    bool ok = expectPin ? (w.preCw == 0x007F && (w.preMx & ~0x3Fu) == 0x1F80 && g_afterCw == 0x007F)
                        : (w.preCw == 0x037F && (w.preMx & 0x8040) == 0x8040 && g_afterCw == 0x037F);
    // (without the pin, the last tick starts with the 037F the previous tick left behind)
    printf("%s pin %s, %s this pointer and tick count kept\n", ok ? "PASS" : "FAIL",
           expectPin ? "on" : "off", thisOk ? "PASS" : "FAIL");
    return ok && thisOk;
}

static DWORD WINAPI Pc24(LPVOID) {
    unsigned c;
    _controlfp_s(&c, _PC_24, _MCW_PC);
    Sleep(INFINITE);
    return 0;
}
static DWORD WINAPI FtzDaz(LPVOID) {
    _mm_setcsr(_mm_getcsr() | 0x8040);
    Sleep(INFINITE);
    return 0;
}
static DWORD WINAPI FlipLater(LPVOID) {
    Sleep(2500);
    unsigned c;
    _controlfp_s(&c, _PC_64, _MCW_PC);
    Sleep(INFINITE);
    return 0;
}

int wmain(int argc, wchar_t** argv) {
    if (argc < 2) { printf("usage: probe-test <logdir>\n"); return 2; }
    wchar_t modPath[MAX_PATH] = L"?";
    DWORD handle = 0, size = GetFileVersionInfoSizeW(L"kernel32.dll", &handle);
    GetModuleFileNameW(GetModuleHandleW(L"version.dll"), modPath, MAX_PATH);
    printf("version.dll loaded from: %ls\n", modPath);
    if (size == 0) { printf("FAIL GetFileVersionInfoSizeW\n"); return 1; }
    BYTE* data = new BYTE[size];
    VS_FIXEDFILEINFO* ffi = NULL;
    UINT len = 0;
    if (!GetFileVersionInfoW(L"kernel32.dll", 0, size, data) ||
        !VerQueryValueW(data, L"\\", (void**)&ffi, &len) || !ffi) {
        printf("FAIL GetFileVersionInfoW/VerQueryValueW\n");
        return 1;
    }
    printf("forwarding OK: kernel32.dll %u.%u.%u.%u\n", HIWORD(ffi->dwFileVersionMS),
           LOWORD(ffi->dwFileVersionMS), HIWORD(ffi->dwFileVersionLS), LOWORD(ffi->dwFileVersionLS));
    char lang[64];
    if (!VerLanguageNameA(0x409, lang, sizeof lang)) { printf("FAIL VerLanguageNameA\n"); return 1; }
    printf("VerLanguageNameA(0x409) = %s\n", lang);

    bool noPin = argc > 2 && wcscmp(argv[2], L"nopin") == 0;
    Sleep(1500);  // let the monitor thread start (it may install the hook)
    if (!CheckPin(!noPin)) return 1;
    if (noPin) {
        Sleep(1500);
        return 0;
    }

    CreateThread(NULL, 0, Pc24, NULL, 0, NULL);
    CreateThread(NULL, 0, FtzDaz, NULL, 0, NULL);
    CreateThread(NULL, 0, FlipLater, NULL, 0, NULL);
    Sleep(1500);

    wchar_t path[MAX_PATH];
    swprintf_s(path, L"%s\\warnings.2099-01-01.00-00-00.txt", argv[1]);
    HANDLE f = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                           CREATE_ALWAYS, 0, NULL);
    const char* l1 = "-- Log file for all dbTracef messages --\r\n\r\n12:00:00.00   normal line\r\n";
    const char* l2 = "12:00:05.66    *** Squad command 45 sent from 1002 (Test) but received by "
                     "squad \"sbps\\races\\axis\\x\" belonging to 1006 (CPU - Normal)\r\n";
    DWORD w;
    WriteFile(f, l1, (DWORD)strlen(l1), &w, NULL);
    Sleep(2500);
    WriteFile(f, l2, (DWORD)strlen(l2), &w, NULL);
    CloseHandle(f);
    Sleep(3000);
    printf("done\n");
    return 0;
}
