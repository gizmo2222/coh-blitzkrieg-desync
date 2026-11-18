// fpu-probe: a version.dll proxy for RelicCOH.exe (Company of Heroes Relaunch).
//
// RelicCOH.exe imports VERSION.dll, which is not a KnownDLL, so Windows loads the copy in the game
// folder first. This DLL forwards all 17 version.dll exports to the real one in the system folder,
// and inside RelicCOH.exe it starts one monitor thread that:
//   - every few seconds suspends each game thread for a moment, reads its x87 control word and
//     MXCSR, and logs them (with thread id, current code location and thread start address);
//   - logs every DLL that gets loaded or unloaded (overlays, hooks);
//   - watches the newest warnings.*.txt and raises an alert at the first
//     "*** Squad command ... sent from" line (the first lockstep mismatch).
// The pinning fix (2.1): SimEngine's World::Simulate runs once per simulation tick. The probe
// puts a jump at its start (in memory; the file on disk is untouched) to a stub that sets x87
// cw=007F (24-bit, round-to-nearest, exceptions masked, what the game's own code sets on its main
// and worker threads) and MXCSR=1F80 before and after the real function, and logs every time the
// value had to be corrected. So every PC runs each tick with the same settings, whatever an overlay
// or driver did to the thread in between. (2.0 wrapped World::SimulatePre / SimulatePost in the
// exe's import table, but the exe calls those only once per game.)
// Tick timing (2.2): the same hook times each tick and the gap between ticks. Each "PIN  ticks="
// line gives the last interval's average and longest tick and its longest gap, and a
// "PIN  slow tick" line marks any gap of 1 s or more (sim stalled, paused or waiting for another
// PC) and any tick that took 250 ms or more. Timing needs the hook, so it is off with nopin.
//
// Log: <Documents>\My Games\Company of Heroes Relaunch\LogFiles\fpuprobe.<date>.<time>.txt
//
// Environment overrides (for testing): FPU_PROBE_FORCE=1 (run in any exe), FPU_PROBE_LOGDIR=<dir>,
// FPU_PROBE_INTERVAL=<ms>, FPU_PROBE_NOBOX=1 (beep only, no message box), FPU_PROBE_NOPIN=1.
// Files next to this DLL: fpu-probe.nobox turns the message box off, fpu-probe.nopin turns the
// pinning off (logging only, as in 1.0).

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <intrin.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <wchar.h>
#include <map>
#include <string>
#include <vector>

#define PROBE_VERSION "2.2"

// ---------------------------------------------------------------------------------------------
// Forwarding to the real version.dll
// ---------------------------------------------------------------------------------------------
static const char* const kNames[] = {
    "GetFileVersionInfoA",     "GetFileVersionInfoByHandle", "GetFileVersionInfoExA",
    "GetFileVersionInfoExW",   "GetFileVersionInfoSizeA",    "GetFileVersionInfoSizeExA",
    "GetFileVersionInfoSizeExW", "GetFileVersionInfoSizeW",  "GetFileVersionInfoW",
    "VerFindFileA",            "VerFindFileW",               "VerInstallFileA",
    "VerInstallFileW",         "VerQueryValueA",             "VerQueryValueW"};
static FARPROC volatile g_real[15];
static HMODULE volatile g_realMod;

static void FatalForward(const char* what) {
    char msg[300];
    _snprintf_s(msg, sizeof msg, _TRUNCATE,
                "fpu-probe (version.dll in the game folder) could not %s.\n"
                "Delete version.dll from the game folder to play without the probe.", what);
    MessageBoxA(NULL, msg, "fpu-probe", MB_OK | MB_ICONERROR);
    TerminateProcess(GetCurrentProcess(), 1);
}

extern "C" FARPROC __stdcall ResolveReal(int i) {
    FARPROC p = g_real[i];
    if (p) return p;
    HMODULE m = g_realMod;
    if (!m) {
        wchar_t path[MAX_PATH];
        UINT n = GetSystemDirectoryW(path, MAX_PATH);  // System32; WOW64 redirects it to SysWOW64
        if (n == 0 || n > MAX_PATH - 20) FatalForward("find the system folder");
        wcscpy_s(path + n, MAX_PATH - n, L"\\version.dll");
        m = LoadLibraryW(path);
        if (!m) FatalForward("load the system version.dll");
        g_realMod = m;
    }
    p = GetProcAddress(m, kNames[i]);
    if (!p) FatalForward(kNames[i]);
    g_real[i] = p;
    return p;
}

// Each export pushes its index, resolves the real function and jumps to it with the caller's
// stack untouched, so no signature is needed. ResolveReal is stdcall: it pops the index itself,
// and only clobbers eax/ecx/edx, which a WINAPI function may clobber anyway.
#define PROXY(i, name) \
    extern "C" __declspec(naked) void p_##name() { __asm push i __asm call ResolveReal __asm jmp eax }
PROXY(0, GetFileVersionInfoA)
PROXY(1, GetFileVersionInfoByHandle)
PROXY(2, GetFileVersionInfoExA)
PROXY(3, GetFileVersionInfoExW)
PROXY(4, GetFileVersionInfoSizeA)
PROXY(5, GetFileVersionInfoSizeExA)
PROXY(6, GetFileVersionInfoSizeExW)
PROXY(7, GetFileVersionInfoSizeW)
PROXY(8, GetFileVersionInfoW)
PROXY(9, VerFindFileA)
PROXY(10, VerFindFileW)
PROXY(11, VerInstallFileA)
PROXY(12, VerInstallFileW)
PROXY(13, VerQueryValueA)
PROXY(14, VerQueryValueW)

// ---------------------------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------------------------
static HMODULE g_self;
static HANDLE g_log = INVALID_HANDLE_VALUE;
static LARGE_INTEGER g_qpf, g_qpc0;
static FILETIME g_startFt;
static DWORD g_monitorTid, g_loadTid, g_loadMx;
static WORD g_loadCw;
static DWORD g_intervalMs = 5000;
static bool g_noBox;
static std::wstring g_logDir, g_logPath;

static std::string Utf8(const std::wstring& w) {
    if (w.empty()) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), NULL, 0, NULL, NULL);
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &s[0], n, NULL, NULL);
    return s;
}

static void Logf(const char* fmt, ...) {
    if (g_log == INVALID_HANDLE_VALUE) return;
    char buf[2048];
    SYSTEMTIME st;
    GetLocalTime(&st);
    LARGE_INTEGER q;
    QueryPerformanceCounter(&q);
    double el = double(q.QuadPart - g_qpc0.QuadPart) / double(g_qpf.QuadPart);
    int k = _snprintf_s(buf, sizeof buf, _TRUNCATE, "%02u:%02u:%02u.%03u %+8.1f  ", st.wHour,
                        st.wMinute, st.wSecond, st.wMilliseconds, el);
    if (k < 0) k = 0;
    va_list ap;
    va_start(ap, fmt);
    _vsnprintf_s(buf + k, sizeof buf - k - 2, _TRUNCATE, fmt, ap);
    va_end(ap);
    size_t len = strlen(buf);
    buf[len++] = '\r';
    buf[len++] = '\n';
    DWORD w;
    WriteFile(g_log, buf, (DWORD)len, &w, NULL);  // one write per line; goes to the OS cache
}

static const char* const kRound[4] = {"near", "down", "up", "zero"};

static std::string DecodeCw(WORD cw) {
    int pc = (cw >> 8) & 3;
    std::string s = pc == 0 ? "pc24" : pc == 2 ? "pc53" : pc == 3 ? "pc64" : "pc??";
    s += ",";
    s += kRound[(cw >> 10) & 3];
    if ((cw & 0x3F) != 0x3F) s += ",exc-on";
    return s;
}

static std::string DecodeMx(DWORD mx) {
    std::string s = kRound[(mx >> 13) & 3];
    if (mx & 0x8000) s += ",ftz";
    if (mx & 0x0040) s += ",daz";
    if (((mx >> 7) & 0x3F) != 0x3F) s += ",exc-on";
    return s;
}

// ---------------------------------------------------------------------------------------------
// Loaded modules (also used to name code addresses)
// ---------------------------------------------------------------------------------------------
struct Mod {
    DWORD base, end;
    std::string name;
    std::wstring path;
};
static std::vector<Mod> g_mods;

static void ScanModules(bool logChanges) {
    HMODULE hm[1024];
    DWORD need = 0;
    if (!K32EnumProcessModules(GetCurrentProcess(), hm, sizeof hm, &need)) return;
    DWORD cnt = need / sizeof(HMODULE);
    if (cnt > 1024) cnt = 1024;
    std::vector<Mod> now;
    now.reserve(cnt);
    for (DWORD i = 0; i < cnt; ++i) {
        MODULEINFO mi;
        wchar_t path[MAX_PATH];
        if (!K32GetModuleInformation(GetCurrentProcess(), hm[i], &mi, sizeof mi)) continue;
        DWORD n = GetModuleFileNameW(hm[i], path, MAX_PATH);
        if (n == 0) continue;
        Mod m;
        m.base = (DWORD)(UINT_PTR)mi.lpBaseOfDll;
        m.end = m.base + mi.SizeOfImage;
        m.path.assign(path, n);
        size_t slash = m.path.find_last_of(L"\\/");
        m.name = Utf8(slash == std::wstring::npos ? m.path : m.path.substr(slash + 1));
        now.push_back(m);
    }
    if (logChanges) {
        for (size_t i = 0; i < now.size(); ++i) {
            bool found = false;
            for (size_t j = 0; j < g_mods.size() && !found; ++j)
                found = g_mods[j].base == now[i].base && g_mods[j].path == now[i].path;
            if (!found)
                Logf("MODULE+ %08X-%08X %s", now[i].base, now[i].end, Utf8(now[i].path).c_str());
        }
        for (size_t j = 0; j < g_mods.size(); ++j) {
            bool found = false;
            for (size_t i = 0; i < now.size() && !found; ++i)
                found = g_mods[j].base == now[i].base && g_mods[j].path == now[i].path;
            if (!found) Logf("MODULE- %s", Utf8(g_mods[j].path).c_str());
        }
    }
    g_mods.swap(now);
}

static std::string AddrName(DWORD a) {
    char buf[300];
    for (size_t i = 0; i < g_mods.size(); ++i)
        if (a >= g_mods[i].base && a < g_mods[i].end) {
            _snprintf_s(buf, sizeof buf, _TRUNCATE, "%s+%X", g_mods[i].name.c_str(),
                        a - g_mods[i].base);
            return buf;
        }
    _snprintf_s(buf, sizeof buf, _TRUNCATE, "%08X", a);
    return buf;
}

// ---------------------------------------------------------------------------------------------
// Thread FPU scan
// ---------------------------------------------------------------------------------------------
typedef LONG(NTAPI* NtQIT_t)(HANDLE, int, PVOID, ULONG, PULONG);
static NtQIT_t g_ntqit;

struct TState {
    WORD cw;
    DWORD mx;
};
static std::map<DWORD, TState> g_th;
static unsigned g_scanNo;

// MXCSR bits 0-5 are sticky exception flags that change all the time; they are not settings.
static DWORD MxSetting(DWORD mx) { return mx & ~0x3Fu; }

static void ScanThreads(const char* tag) {
    ++g_scanNo;
    ScanModules(true);

    std::vector<DWORD> tids;
    DWORD pid = GetCurrentProcessId();
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snap != INVALID_HANDLE_VALUE) {
        THREADENTRY32 te;
        te.dwSize = sizeof te;
        for (BOOL ok = Thread32First(snap, &te); ok; ok = Thread32Next(snap, &te))
            if (te.th32OwnerProcessID == pid && te.th32ThreadID != g_monitorTid)
                tids.push_back(te.th32ThreadID);
        CloseHandle(snap);
    }

    struct Row {
        DWORD tid, mx, eip, start;
        WORD cw;
        bool ok;
    };
    std::vector<Row> rows;
    rows.reserve(tids.size());
    for (size_t i = 0; i < tids.size(); ++i) {
        Row r = {tids[i], 0, 0, 0, 0, false};
        HANDLE h = OpenThread(THREAD_GET_CONTEXT | THREAD_SUSPEND_RESUME | THREAD_QUERY_INFORMATION,
                              FALSE, r.tid);
        if (!h) continue;  // thread already gone
        if (g_ntqit) {
            PVOID start = NULL;
            if (g_ntqit(h, 9 /*ThreadQuerySetWin32StartAddress*/, &start, sizeof start, NULL) >= 0)
                r.start = (DWORD)(UINT_PTR)start;
        }
        CONTEXT ctx;
        memset(&ctx, 0, sizeof ctx);
        ctx.ContextFlags = CONTEXT_CONTROL | CONTEXT_FLOATING_POINT | CONTEXT_EXTENDED_REGISTERS;
        // Nothing but GetThreadContext between suspend and resume: no heap, no locks, no logging.
        if (SuspendThread(h) != (DWORD)-1) {
            r.ok = GetThreadContext(h, &ctx) != FALSE;
            ResumeThread(h);
        }
        CloseHandle(h);
        if (r.ok) {
            r.cw = (WORD)ctx.FloatSave.ControlWord;
            memcpy(&r.mx, ctx.ExtendedRegisters + 24, 4);  // FXSAVE layout: MXCSR at byte 24
            r.eip = ctx.Eip;
        }
        rows.push_back(r);
    }

    std::map<DWORD, TState> next;
    std::map<std::string, int> combos;
    int changed = 0;
    for (size_t i = 0; i < rows.size(); ++i) {
        const Row& r = rows[i];
        if (!r.ok) {
            Logf("%-5s #%u tid=%-6u (context not readable) start=%s", tag, g_scanNo, r.tid,
                 AddrName(r.start).c_str());
            continue;
        }
        char mark[64] = "";
        std::map<DWORD, TState>::const_iterator it = g_th.find(r.tid);
        if (it == g_th.end()) {
            strcpy_s(mark, " NEW");
        } else if (it->second.cw != r.cw || MxSetting(it->second.mx) != MxSetting(r.mx)) {
            _snprintf_s(mark, sizeof mark, _TRUNCATE, " CHANGED was cw=%04X mx=%04X", it->second.cw,
                        it->second.mx);
            ++changed;
        }
        TState s = {r.cw, r.mx};
        next[r.tid] = s;
        char key[32];
        _snprintf_s(key, sizeof key, _TRUNCATE, "%04X/%04X", r.cw, MxSetting(r.mx));
        combos[key]++;
        Logf("%-5s #%u tid=%-6u cw=%04X %-14s mx=%04X %-12s at=%-28s start=%s%s", tag, g_scanNo,
             r.tid, r.cw, DecodeCw(r.cw).c_str(), r.mx, DecodeMx(r.mx).c_str(),
             AddrName(r.eip).c_str(), AddrName(r.start).c_str(), mark);
    }
    for (std::map<DWORD, TState>::const_iterator it = g_th.begin(); it != g_th.end(); ++it)
        if (next.find(it->first) == next.end())
            Logf("%-5s #%u tid=%-6u EXITED", tag, g_scanNo, it->first);
    g_th.swap(next);

    std::string sum;
    for (std::map<std::string, int>::const_iterator it = combos.begin(); it != combos.end(); ++it) {
        char b[48];
        _snprintf_s(b, sizeof b, _TRUNCATE, "%s%s x%d", sum.empty() ? "" : ", ", it->first.c_str(),
                    it->second);
        sum += b;
    }
    Logf("%-5s #%u SUMMARY threads=%u changed=%d cw/mx: %s", tag, g_scanNo, (unsigned)rows.size(),
         changed, sum.c_str());
}

// ---------------------------------------------------------------------------------------------
// Pinning: detour SimEngine's World::Simulate, which runs once per simulation tick
// ---------------------------------------------------------------------------------------------
static const WORD kPinCw = 0x007F;
static const DWORD kPinMx = 0x1F80;
static const char kSimDll[] = "SimEngine.dll";
static const char kSimTick[] = "?Simulate@World@@UAEXXZ";
// First bytes of World::Simulate in the Relaunch SimEngine.dll: push ecx; push ebx; push esi;
// mov esi,ecx. They do not depend on where they sit, so the trampoline can run them elsewhere.
static const BYTE kSimPrologue[5] = {0x51, 0x53, 0x56, 0x8B, 0xF1};

static bool g_pinWanted, g_pinOn;
static char g_pinStatus[200] = "PIN  not attempted";
extern "C" void* g_simTramp = NULL;  // runs the 5 saved bytes, then jumps to World::Simulate+5
static volatile LONG g_ticks, g_fixPre, g_fixPost, g_firstDone;
static volatile DWORD g_simTid;
static LONG g_lastTicks = -1;

// Tick timing (2.2), in microseconds. The sim thread adds to these; the monitor thread reads and
// resets them for each "PIN  ticks=" line. A gap is the time from one tick's start to the next one's
// (the game runs 8 ticks/s, so about 125 ms; a lockstep wait for another PC shows as a long gap).
static const LONG kSlowGapUs = 1000000, kSlowTickUs = 250000;
static LONGLONG g_tickStartQpc, g_lastStartQpc;
static volatile LONG g_tSumUs, g_tMaxUs, g_tGapMaxUs, g_tCount, g_tSlow, g_slowTotal;
static DWORD g_sumAt;

static LONG QpcUs(LONGLONG d) {
    LONGLONG us = d * 1000000 / g_qpf.QuadPart;
    return us < 0 ? 0 : us > 0x7FFFFFFF ? 0x7FFFFFFF : (LONG)us;
}
static void NoteMax(volatile LONG* m, LONG v) {
    LONG o;
    while (v > (o = *m) && InterlockedCompareExchange(m, v, o) != o) {}
}
// Integer formatting only: this runs on the sim thread, before the pin check.
static void NoteSlow(bool gap, LONG us) {
    LONG n = InterlockedIncrement(&g_slowTotal);
    InterlockedIncrement(&g_tSlow);
    if (n <= 50 || n % 100 == 0) {
        if (gap)
            Logf("PIN  slow tick %d: started %d ms after tick %d (slow #%d)", g_ticks, us / 1000,
                 g_ticks - 1, n);
        else
            Logf("PIN  slow tick %d: took %d ms (slow #%d)", g_ticks, us / 1000, n);
    }
}
static void TimeTick(int post) {
    LARGE_INTEGER q;
    QueryPerformanceCounter(&q);
    if (!post) {
        if (g_lastStartQpc) {
            LONG gap = QpcUs(q.QuadPart - g_lastStartQpc);
            NoteMax(&g_tGapMaxUs, gap);
            if (gap >= kSlowGapUs) NoteSlow(true, gap);
        }
        g_lastStartQpc = g_tickStartQpc = q.QuadPart;
    } else if (g_tickStartQpc) {
        LONG d = QpcUs(q.QuadPart - g_tickStartQpc);
        InterlockedExchangeAdd(&g_tSumUs, d);
        InterlockedIncrement(&g_tCount);
        NoteMax(&g_tMaxUs, d);
        if (d >= kSlowTickUs) NoteSlow(false, d);
    }
}

// Called from hk_Simulate on the simulation thread, before (post=0) and after (post=1) each tick.
extern "C" void __stdcall PinCheck(int post) {
    if (!post) InterlockedIncrement(&g_ticks);
    TimeTick(post);  // first, so anything its logging does to cw/mx is still checked below
    WORD cw;
    DWORD mx;
    __asm fnstcw cw
    __asm stmxcsr mx
    DWORD tid = GetCurrentThreadId();
    if (!post) {
        if (InterlockedExchange(&g_firstDone, 1) == 0) {
            g_simTid = tid;
            Logf("PIN  first tick on tid=%u, game had cw=%04X %s mx=%04X %s", tid, cw,
                 DecodeCw(cw).c_str(), mx, DecodeMx(mx).c_str());
        } else if (tid != g_simTid) {
            Logf("PIN  tick now on tid=%u (was %u)", tid, g_simTid);
            g_simTid = tid;
        }
    }
    if (cw == kPinCw && MxSetting(mx) == kPinMx) return;
    WORD ncw = kPinCw;
    DWORD nmx = (mx & 0x3Fu) | kPinMx;  // keep the sticky flags
    __asm fldcw ncw
    __asm ldmxcsr nmx
    LONG n = InterlockedIncrement(post ? &g_fixPost : &g_fixPre);
    if (n <= 20 || n % 1000 == 0)
        Logf("PIN  %s tick %d: fixed cw=%04X %s mx=%04X %s -> cw=%04X mx=%04X (fix #%d) tid=%u",
             post ? "after " : "before", g_ticks, cw, DecodeCw(cw).c_str(), mx, DecodeMx(mx).c_str(),
             ncw, nmx, n, tid);
}

// World::Simulate is thiscall with no stack arguments: keep ecx (this) for the real call.
extern "C" __declspec(naked) void hk_Simulate() {
    __asm push ecx
    __asm push 0
    __asm call PinCheck
    __asm pop ecx
    __asm call dword ptr [g_simTramp]
    __asm push 1
    __asm call PinCheck
    __asm ret
}

static bool PinFail(const char* why) {
    _snprintf_s(g_pinStatus, sizeof g_pinStatus, _TRUNCATE, "PIN  FAILED: %s (logging only)", why);
    g_pinWanted = false;
    return true;
}

// Writes a 5-byte jmp to hk_Simulate over the start of World::Simulate (in memory only).
// Safe to call again; returns false while SimEngine.dll is not loaded yet, true when done.
static bool TryInstallPin() {
    if (g_pinOn || !g_pinWanted) return true;
    HMODULE sim = GetModuleHandleA(kSimDll);
    if (!sim) return false;
    BYTE* fn = (BYTE*)GetProcAddress(sim, kSimTick);
    if (!fn) return PinFail("SimEngine.dll has no World::Simulate export");
    if (memcmp(fn, kSimPrologue, sizeof kSimPrologue) != 0) {
        char why[120];
        _snprintf_s(why, sizeof why, _TRUNCATE,
                    "World::Simulate starts with %02X %02X %02X %02X %02X, not the known bytes",
                    fn[0], fn[1], fn[2], fn[3], fn[4]);
        return PinFail(why);
    }
    BYTE* tr = (BYTE*)VirtualAlloc(NULL, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!tr) return PinFail("VirtualAlloc for the trampoline failed");
    memcpy(tr, fn, 5);
    tr[5] = 0xE9;
    *(LONG*)(tr + 6) = (LONG)(fn + 5 - (tr + 10));
    FlushInstructionCache(GetCurrentProcess(), tr, 16);
    g_simTramp = tr;

    DWORD old;
    if (!VirtualProtect(fn, 8, PAGE_EXECUTE_READWRITE, &old)) return PinFail("VirtualProtect failed");
    LONGLONG cur = *(volatile LONGLONG*)fn, patched = cur;
    BYTE* p = (BYTE*)&patched;
    p[0] = 0xE9;
    *(LONG*)(p + 1) = (LONG)((BYTE*)hk_Simulate - (fn + 5));
    if (((ULONG_PTR)fn & 7) == 0)
        InterlockedCompareExchange64((volatile LONGLONG*)fn, patched, cur);  // one atomic write
    else
        memcpy(fn, p, 5);
    VirtualProtect(fn, 8, old, &old);
    FlushInstructionCache(GetCurrentProcess(), fn, 8);
    g_pinOn = true;
    _snprintf_s(g_pinStatus, sizeof g_pinStatus, _TRUNCATE,
                "PIN  on: every sim tick starts and ends with cw=%04X mx=%04X (World::Simulate at "
                "SimEngine.dll+%X hooked)", kPinCw, kPinMx, (unsigned)(fn - (BYTE*)sim));
    return true;
}

static void LogPinSummary() {
    LONG ticks = g_ticks;
    if (!g_pinOn || ticks == g_lastTicks) return;
    DWORD now = GetTickCount();
    LONG n = InterlockedExchange(&g_tCount, 0), sum = InterlockedExchange(&g_tSumUs, 0);
    LONG tmax = InterlockedExchange(&g_tMaxUs, 0), gmax = InterlockedExchange(&g_tGapMaxUs, 0);
    LONG slow = InterlockedExchange(&g_tSlow, 0);
    double secs = g_lastTicks < 0 ? 0.0 : (now - g_sumAt) / 1000.0;
    Logf("PIN  ticks=%d fixed before=%d after=%d sim tid=%u; last %.1f s: +%d ticks, tick ms "
         "avg=%.1f max=%.1f, gap ms max=%.0f, slow=%d",
         ticks, g_fixPre, g_fixPost, g_simTid, secs, ticks - (g_lastTicks < 0 ? 0 : g_lastTicks),
         n ? sum / 1000.0 / n : 0.0, tmax / 1000.0, gmax / 1000.0, slow);
    g_lastTicks = ticks;
    g_sumAt = now;
}

// ---------------------------------------------------------------------------------------------
// warnings.*.txt watcher and alert
// ---------------------------------------------------------------------------------------------
static std::wstring g_wName;
static ULONGLONG g_wOff;
static bool g_wFromEnd, g_alerted;
static std::string g_wBuf;

static DWORD WINAPI AlertBoxThread(LPVOID p) {
    wchar_t* text = (wchar_t*)p;
    for (int i = 0; i < 3; ++i) Beep(1000, 150), Sleep(100);
    if (!g_noBox)
        MessageBoxW(NULL, text, L"fpu-probe: desync detected",
                    MB_OK | MB_ICONWARNING | MB_TOPMOST);
    delete[] text;
    return 0;
}

static void Alert(const std::string& line) {
    g_alerted = true;
    Logf("ALERT first mismatch line in %s: %s", Utf8(g_wName).c_str(), line.c_str());
    ScanThreads("ALERT");
    Logf("ALERT done. The probe keeps logging until the game closes.");

    std::string clock = line.substr(0, line.find_first_of(" \t"));
    std::wstring msg = L"First desync line in the game log at ";
    msg += std::wstring(clock.begin(), clock.end());
    msg += L":\n\n";
    std::wstring wl(line.size(), L'\0');
    int n = MultiByteToWideChar(CP_ACP, 0, line.c_str(), (int)line.size(), &wl[0], (int)wl.size());
    wl.resize(n > 0 ? n : 0);
    msg += wl;
    msg += L"\n\nFPU state at this moment was written to:\n";
    msg += g_logPath;
    msg += L"\n\nAfter the game, send that file and the warnings file to the group.";
    wchar_t* copy = new wchar_t[msg.size() + 1];
    wcscpy_s(copy, msg.size() + 1, msg.c_str());
    HANDLE t = CreateThread(NULL, 0, AlertBoxThread, copy, 0, NULL);
    if (t) CloseHandle(t); else delete[] copy;
}

static bool IsMismatchLine(const char* s) {
    return strstr(s, "*** ") && strstr(s, " command ") && strstr(s, " sent from ");
}

static void PollWarnings() {
    if (g_alerted) return;
    WIN32_FIND_DATAW fd;
    HANDLE f = FindFirstFileW((g_logDir + L"\\warnings.*.txt").c_str(), &fd);
    if (f == INVALID_HANDLE_VALUE) return;
    std::wstring best;
    FILETIME bestWrite = {0, 0}, bestCreate = {0, 0};
    do {
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        if (best.empty() || CompareFileTime(&fd.ftLastWriteTime, &bestWrite) > 0) {
            best = fd.cFileName;
            bestWrite = fd.ftLastWriteTime;
            bestCreate = fd.ftCreationTime;
        }
    } while (FindNextFileW(f, &fd));
    FindClose(f);
    if (best.empty()) return;

    if (best != g_wName) {
        // A file created after the game started is this session's log: read it all.
        // An older file: only read what is appended from now on.
        ULARGE_INTEGER s, c;
        s.LowPart = g_startFt.dwLowDateTime, s.HighPart = g_startFt.dwHighDateTime;
        c.LowPart = bestCreate.dwLowDateTime, c.HighPart = bestCreate.dwHighDateTime;
        bool fresh = c.QuadPart + 2ull * 10000000ull >= s.QuadPart;
        g_wName = best;
        g_wOff = 0;
        g_wFromEnd = !fresh;
        g_wBuf.clear();
        Logf("WATCH %s (%s)", Utf8(best).c_str(),
             fresh ? "created this session, reading from the start" : "older file, new lines only");
    }

    HANDLE h = CreateFileW((g_logDir + L"\\" + g_wName).c_str(), GENERIC_READ,
                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                           OPEN_EXISTING, 0, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    LARGE_INTEGER size;
    if (!GetFileSizeEx(h, &size)) { CloseHandle(h); return; }
    if (g_wFromEnd) g_wOff = size.QuadPart, g_wFromEnd = false;
    if ((ULONGLONG)size.QuadPart < g_wOff) g_wOff = 0, g_wBuf.clear();  // file was rewritten

    static char chunk[65536];
    ULONGLONG budget = 8u << 20;  // at most 8 MB per poll
    while (g_wOff < (ULONGLONG)size.QuadPart && budget > 0 && !g_alerted) {
        LARGE_INTEGER pos;
        pos.QuadPart = (LONGLONG)g_wOff;
        DWORD got = 0;
        if (!SetFilePointerEx(h, pos, NULL, FILE_BEGIN) ||
            !ReadFile(h, chunk, sizeof chunk, &got, NULL) || got == 0)
            break;
        g_wOff += got;
        budget = budget > got ? budget - got : 0;
        g_wBuf.append(chunk, got);
        size_t startPos = 0, nl;
        while ((nl = g_wBuf.find('\n', startPos)) != std::string::npos) {
            std::string line = g_wBuf.substr(startPos, nl - startPos);
            startPos = nl + 1;
            while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
            if (IsMismatchLine(line.c_str())) {
                Alert(line);
                break;
            }
        }
        g_wBuf.erase(0, startPos);
        if (g_wBuf.size() > 65536) g_wBuf.clear();  // no newline in 64 KB: not a text log
    }
    CloseHandle(h);
}

// ---------------------------------------------------------------------------------------------
// Monitor thread
// ---------------------------------------------------------------------------------------------
static std::wstring EnvW(const wchar_t* name) {
    wchar_t buf[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(name, buf, MAX_PATH);
    return (n > 0 && n < MAX_PATH) ? std::wstring(buf, n) : std::wstring();
}

static std::wstring DocumentsLogDir() {
    typedef HRESULT(WINAPI * GetPath_t)(HWND, int, HANDLE, DWORD, LPWSTR);
    HMODULE sh = LoadLibraryW(L"shell32.dll");
    GetPath_t getPath = sh ? (GetPath_t)GetProcAddress(sh, "SHGetFolderPathW") : NULL;
    wchar_t docs[MAX_PATH];
    if (!getPath || getPath(NULL, 0x0005 /*CSIDL_PERSONAL*/, NULL, 0, docs) != S_OK) {
        DWORD n = GetEnvironmentVariableW(L"USERPROFILE", docs, MAX_PATH);
        if (n == 0 || n >= MAX_PATH - 12) return std::wstring();
        wcscat_s(docs, L"\\Documents");
    }
    return std::wstring(docs) + L"\\My Games\\Company of Heroes Relaunch\\LogFiles";
}

static void MakeDirs(const std::wstring& dir) {
    for (size_t i = 3; i <= dir.size(); ++i)
        if (i == dir.size() || dir[i] == L'\\') CreateDirectoryW(dir.substr(0, i).c_str(), NULL);
}

static void LogHeader() {
    wchar_t exe[MAX_PATH];
    GetModuleFileNameW(NULL, exe, MAX_PATH);
    wchar_t self[MAX_PATH];
    GetModuleFileNameW(g_self, self, MAX_PATH);
    SYSTEMTIME st;
    GetLocalTime(&st);
    Logf("fpu-probe " PROBE_VERSION " started %04u-%02u-%02u, pid %u", st.wYear, st.wMonth, st.wDay,
         GetCurrentProcessId());
    Logf("INFO exe: %s", Utf8(exe).c_str());
    Logf("INFO probe: %s", Utf8(self).c_str());
    Logf("INFO command line: %s", Utf8(GetCommandLineW()).c_str());

    int r[4];
    char vendor[13] = {0};
    __cpuid(r, 0);
    memcpy(vendor, &r[1], 4), memcpy(vendor + 4, &r[3], 4), memcpy(vendor + 8, &r[2], 4);
    char brand[49] = {0};
    __cpuid(r, 0x80000000);
    if ((unsigned)r[0] >= 0x80000004u)
        for (int i = 0; i < 3; ++i) __cpuid((int*)(brand + 16 * i), 0x80000002 + i);
    __cpuid(r, 1);
    unsigned fam = (r[0] >> 8) & 0xF, model = (r[0] >> 4) & 0xF, step = r[0] & 0xF;
    if (fam == 0xF) fam += (r[0] >> 20) & 0xFF;
    if (fam == 0x6 || fam >= 0xF) model += ((r[0] >> 16) & 0xF) << 4;
    const char* b = brand;
    while (*b == ' ') ++b;
    Logf("INFO cpu: %s | %s | family %Xh model %Xh stepping %u | %u logical processors", vendor, b,
         fam, model, step, (unsigned)GetActiveProcessorCount(ALL_PROCESSOR_GROUPS));

    typedef LONG(WINAPI * RtlGetVersion_t)(OSVERSIONINFOW*);
    RtlGetVersion_t rgv = (RtlGetVersion_t)GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion");
    OSVERSIONINFOW ov;
    memset(&ov, 0, sizeof ov);
    ov.dwOSVersionInfoSize = sizeof ov;
    if (rgv && rgv(&ov) == 0)
        Logf("INFO windows: %u.%u build %u", ov.dwMajorVersion, ov.dwMinorVersion, ov.dwBuildNumber);
    Logf("INFO at DLL load: tid=%u cw=%04X %s mx=%04X %s", g_loadTid, g_loadCw,
         DecodeCw(g_loadCw).c_str(), g_loadMx, DecodeMx(g_loadMx).c_str());
    Logf("INFO scan every %u ms. cw = x87 control word, mx = MXCSR (raw; bits 0-5 are sticky flags,",
         g_intervalMs);
    Logf("INFO ignored for CHANGED). pc24/53/64 = x87 precision, near/down/up/zero = rounding,");
    Logf("INFO ftz/daz = SSE flush-to-zero / denormals-are-zero. at = where the thread was, start =");
    Logf("INFO thread start address. Compare the SUMMARY lines of all four players' logs.");
}

static DWORD WINAPI MonitorThread(LPVOID) {
    g_monitorTid = GetCurrentThreadId();
    g_logDir = EnvW(L"FPU_PROBE_LOGDIR");
    if (g_logDir.empty()) g_logDir = DocumentsLogDir();
    if (g_logDir.empty()) return 0;
    MakeDirs(g_logDir);

    SYSTEMTIME st;
    GetLocalTime(&st);
    wchar_t name[64];
    _snwprintf_s(name, _TRUNCATE, L"\\fpuprobe.%04u-%02u-%02u.%02u-%02u-%02u.txt", st.wYear,
                 st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
    g_logPath = g_logDir + name;
    g_log = CreateFileW(g_logPath.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                        NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (g_log == INVALID_HANDLE_VALUE) return 0;

    g_ntqit = (NtQIT_t)GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtQueryInformationThread");
    LogHeader();
    ScanModules(false);
    for (size_t i = 0; i < g_mods.size(); ++i)
        Logf("MODULE  %08X-%08X %s", g_mods[i].base, g_mods[i].end, Utf8(g_mods[i].path).c_str());

    bool pinLogged = TryInstallPin();
    Logf("%s", pinLogged ? g_pinStatus : "PIN  waiting for SimEngine.dll to load");
    DWORD lastScan = GetTickCount() - g_intervalMs;
    for (;;) {
        DWORD now = GetTickCount();
        if (now - lastScan >= g_intervalMs) {
            lastScan = now;
            ScanThreads("SCAN");
            LogPinSummary();
        }
        if (!pinLogged && TryInstallPin()) {
            pinLogged = true;
            Logf("%s", g_pinStatus);
        }
        PollWarnings();
        Sleep(500);
    }
}

// ---------------------------------------------------------------------------------------------
BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = inst;
        DisableThreadLibraryCalls(inst);

        wchar_t exe[MAX_PATH];
        DWORD n = GetModuleFileNameW(NULL, exe, MAX_PATH);
        const wchar_t* base = exe;
        for (DWORD i = 0; i < n; ++i)
            if (exe[i] == L'\\' || exe[i] == L'/') base = exe + i + 1;
        bool force = GetEnvironmentVariableW(L"FPU_PROBE_FORCE", NULL, 0) > 0;
        if (!force && _wcsicmp(base, L"RelicCOH.exe") != 0) return TRUE;  // forward only

        WORD cw;
        DWORD mx;
        __asm fnstcw cw
        __asm stmxcsr mx
        g_loadCw = cw;
        g_loadMx = mx;
        g_loadTid = GetCurrentThreadId();
        QueryPerformanceFrequency(&g_qpf);
        QueryPerformanceCounter(&g_qpc0);
        GetSystemTimeAsFileTime(&g_startFt);

        wchar_t v[32];
        DWORD vn = GetEnvironmentVariableW(L"FPU_PROBE_INTERVAL", v, 32);
        if (vn > 0 && vn < 32) {
            DWORD ms = (DWORD)_wtoi(v);
            if (ms >= 200) g_intervalMs = ms;
        }
        g_noBox = GetEnvironmentVariableW(L"FPU_PROBE_NOBOX", NULL, 0) > 0;
        bool noPin = false;
        wchar_t flag[MAX_PATH];
        DWORD fl = GetModuleFileNameW(inst, flag, MAX_PATH);
        if (fl > 0 && fl < MAX_PATH - 20) {
            wchar_t* slash = wcsrchr(flag, L'\\');
            if (slash) {
                wcscpy_s(slash + 1, MAX_PATH - (slash + 1 - flag), L"fpu-probe.nobox");
                if (GetFileAttributesW(flag) != INVALID_FILE_ATTRIBUTES) g_noBox = true;
                wcscpy_s(slash + 1, MAX_PATH - (slash + 1 - flag), L"fpu-probe.nopin");
                if (GetFileAttributesW(flag) != INVALID_FILE_ATTRIBUTES) noPin = true;
            }
        }
        if (GetEnvironmentVariableW(L"FPU_PROBE_NOPIN", NULL, 0) > 0) noPin = true;
        g_pinWanted = !noPin;
        if (noPin)
            strcpy_s(g_pinStatus, "PIN  off (fpu-probe.nopin or FPU_PROBE_NOPIN): logging only, as in 1.0");
        else
            TryInstallPin();  // the monitor thread retries if SimEngine.dll is not loaded yet

        // The thread starts running after the loader lock is released.
        HANDLE t = CreateThread(NULL, 0, MonitorThread, NULL, 0, &g_monitorTid);
        if (t) CloseHandle(t);
    } else if (reason == DLL_PROCESS_DETACH && g_log != INVALID_HANDLE_VALUE) {
        LogPinSummary();
        Logf("EXIT process is shutting down (%s)", reserved ? "normal exit" : "DLL unloaded");
    }
    return TRUE;
}
