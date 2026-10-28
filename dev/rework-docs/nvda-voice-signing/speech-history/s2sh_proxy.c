/* nvdaControllerClient.dll for the SAPI2SR bridge: forwards every call to
 * NV Access's original (nvdaControllerClient.nvaccess.dll, same folder) and
 * publishes each spoken text in the shared speech history (s2sh_shared.h).
 *
 * Rules this file keeps:
 *  - Speech always comes first. The call is forwarded before anything is
 *    published, and publishing never blocks for long (lock wait 20 ms, then
 *    the entry is dropped) and never fails a call.
 *  - The ring is readable only by the current user, and not by processes
 *    below medium integrity (sandboxed browsers and the like).
 *  - Nothing is published unless a reader asked for this process
 *    (S2SH_WANT_PREFIX, see s2sh_shared.h). Which program's speech is
 *    recorded, and when, is the reader's decision; this file knows no program.
 */
#include <windows.h>
#include <sddl.h>
#include "s2sh_shared.h"

typedef unsigned long error_status_t;
typedef error_status_t (__stdcall *FnVoid)(void);
typedef error_status_t (__stdcall *FnText)(const wchar_t *);
typedef error_status_t (__stdcall *FnPid)(unsigned long *);
typedef error_status_t (__stdcall *FnSsml)(const wchar_t *, int, int, unsigned char);
typedef error_status_t (__stdcall *FnMarkCb)(error_status_t (__stdcall *)(const wchar_t *));

static HMODULE g_self;

/* ---------- the original NVDA client ---------- */

static INIT_ONCE g_realOnce = INIT_ONCE_STATIC_INIT;
static HMODULE g_real;

static BOOL CALLBACK LoadReal(PINIT_ONCE once, PVOID param, PVOID *ctx)
{
    WCHAR path[MAX_PATH + 64];
    DWORD n = GetModuleFileNameW(g_self, path, MAX_PATH);
    (void)once; (void)param; (void)ctx;
    if (n == 0 || n >= MAX_PATH)
        return TRUE;
    while (n > 0 && path[n - 1] != L'\\')
        n--;
    lstrcpyW(path + n, L"nvdaControllerClient.nvaccess.dll");
    g_real = LoadLibraryW(path);
    return TRUE;
}

static FARPROC Real(const char *name)
{
    InitOnceExecuteOnce(&g_realOnce, LoadReal, NULL, NULL);
    return g_real ? GetProcAddress(g_real, name) : NULL;
}

/* ---------- the shared ring ---------- */

static INIT_ONCE g_ringOnce = INIT_ONCE_STATIC_INIT;
static S2shMap *g_ring;
static HANDLE g_lock;

static BOOL PublishEnabled(void)
{
    WCHAR ini[MAX_PATH + 64];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", ini, MAX_PATH);
    if (n == 0 || n >= MAX_PATH)
        return TRUE;
    lstrcatW(ini, L"\\SAPI2SR\\SpeechHistory.ini");
    return GetPrivateProfileIntW(L"SpeechHistory", L"Publish", 1, ini) != 0;
}

/* Owner-only DACL for the current user (plus SYSTEM), medium-integrity label
 * with no-read-up and no-write-up. */
static BOOL MakeSecurity(SECURITY_ATTRIBUTES *sa)
{
    HANDLE token;
    BYTE buf[256];
    DWORD got;
    LPWSTR sid = NULL;
    WCHAR sddl[256];
    BOOL ok = FALSE;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
        return FALSE;
    if (GetTokenInformation(token, TokenUser, buf, sizeof(buf), &got)
            && ConvertSidToStringSidW(((TOKEN_USER *)buf)->User.Sid, &sid)) {
        wsprintfW(sddl, L"D:P(A;;GA;;;SY)(A;;GA;;;%s)S:(ML;;NWNR;;;ME)", sid);
        sa->nLength = sizeof(*sa);
        sa->bInheritHandle = FALSE;
        ok = ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, SDDL_REVISION_1,
                &sa->lpSecurityDescriptor, NULL);
        LocalFree(sid);
    }
    CloseHandle(token);
    return ok;
}

static BOOL CALLBACK OpenRing(PINIT_ONCE once, PVOID param, PVOID *ctx)
{
    SECURITY_ATTRIBUTES sa;
    SECURITY_ATTRIBUTES *psa = NULL;
    HANDLE map;
    S2shMap *view;
    (void)once; (void)param; (void)ctx;
    if (!PublishEnabled())
        return TRUE;
    ZeroMemory(&sa, sizeof(sa));
    if (MakeSecurity(&sa))
        psa = &sa;
    g_lock = CreateMutexW(psa, FALSE, S2SH_LOCK_NAME);
    map = CreateFileMappingW(INVALID_HANDLE_VALUE, psa, PAGE_READWRITE, 0, sizeof(S2shMap), S2SH_MAP_NAME);
    if (psa)
        LocalFree(sa.lpSecurityDescriptor);
    if (!g_lock || !map)
        goto fail;
    view = (S2shMap *)MapViewOfFile(map, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(S2shMap));
    if (!view)
        goto fail;
    /* The handle stays open for the life of the process: a named section
     * leaves the namespace with its last HANDLE, even while views remain,
     * and readers could no longer open it. */
    g_ring = view;
    return TRUE;
fail:
    if (map)
        CloseHandle(map);
    if (g_lock)
        CloseHandle(g_lock);
    g_lock = NULL;
    return TRUE;
}

/* Does a reader ask for this process right now? One kernel call per text,
 * because the request comes and goes while the process runs. */
static BOOL Wanted(void)
{
    WCHAR name[96];
    HANDLE h;
    wsprintfW(name, L"%s%lu", S2SH_WANT_PREFIX, GetCurrentProcessId());
    h = OpenEventW(SYNCHRONIZE, FALSE, name);
    if (!h)
        return FALSE;
    CloseHandle(h);
    return TRUE;
}

static void Publish(const wchar_t *text, DWORD kind)
{
    DWORD wait, len, i;
    ULONGLONG seq;
    S2shEntry *e;
    FILETIME now;
    if (!text)
        return;
    /* the ring is created even when nobody asks, so a reader can open it
     * before its program first speaks */
    InitOnceExecuteOnce(&g_ringOnce, OpenRing, NULL, NULL);
    if (!g_ring || !Wanted())
        return;
    wait = WaitForSingleObject(g_lock, 20);
    if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED)
        return;
    if (g_ring->magic != S2SH_MAGIC) {
        /* first writer: the section came up zeroed */
        g_ring->version = S2SH_VERSION;
        g_ring->entryCount = S2SH_ENTRIES;
        g_ring->entryChars = S2SH_CHARS;
        g_ring->headerSize = (DWORD)FIELD_OFFSET(S2shMap, entries);
        g_ring->entrySize = (DWORD)sizeof(S2shEntry);
        g_ring->lastSeq = 0;
        g_ring->magic = S2SH_MAGIC;
    }
    seq = g_ring->lastSeq + 1;
    e = &g_ring->entries[(seq - 1) % S2SH_ENTRIES];
    e->seq = 0;
    for (len = 0; len < S2SH_CHARS && text[len]; len++)
        ;
    for (i = 0; i < len; i++)
        e->text[i] = text[i];
    e->text[len] = 0;
    e->length = len;
    e->truncated = text[len] ? 1 : 0;
    e->kind = kind;
    e->pid = GetCurrentProcessId();
    GetSystemTimeAsFileTime(&now);
    e->time = ((ULONGLONG)now.dwHighDateTime << 32) | now.dwLowDateTime;
    e->seq = seq;
    g_ring->lastSeq = seq;
    ReleaseMutex(g_lock);
}

/* ---------- the exports ---------- */

#define NOT_LOADED ERROR_MOD_NOT_FOUND

error_status_t __stdcall nvdaController_testIfRunning(void)
{
    FnVoid f = (FnVoid)Real("nvdaController_testIfRunning");
    return f ? f() : NOT_LOADED;
}

error_status_t __stdcall nvdaController_speakText(const wchar_t *text)
{
    FnText f = (FnText)Real("nvdaController_speakText");
    error_status_t r = f ? f(text) : NOT_LOADED;
    Publish(text, S2SH_KIND_TEXT);
    return r;
}

error_status_t __stdcall nvdaController_speakSsml(const wchar_t *ssml, int symbolLevel, int priority, unsigned char asynchronous)
{
    FnSsml f = (FnSsml)Real("nvdaController_speakSsml");
    error_status_t r = f ? f(ssml, symbolLevel, priority, asynchronous) : NOT_LOADED;
    Publish(ssml, S2SH_KIND_SSML);
    return r;
}

error_status_t __stdcall nvdaController_cancelSpeech(void)
{
    FnVoid f = (FnVoid)Real("nvdaController_cancelSpeech");
    return f ? f() : NOT_LOADED;
}

error_status_t __stdcall nvdaController_brailleMessage(const wchar_t *message)
{
    FnText f = (FnText)Real("nvdaController_brailleMessage");
    return f ? f(message) : NOT_LOADED;
}

error_status_t __stdcall nvdaController_getProcessId(unsigned long *pid)
{
    FnPid f = (FnPid)Real("nvdaController_getProcessId");
    return f ? f(pid) : NOT_LOADED;
}

error_status_t __stdcall nvdaController_setOnSsmlMarkReachedCallback(error_status_t (__stdcall *callback)(const wchar_t *))
{
    FnMarkCb f = (FnMarkCb)Real("nvdaController_setOnSsmlMarkReachedCallback");
    return f ? f(callback) : NOT_LOADED;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = inst;
        DisableThreadLibraryCalls(inst);
    }
    return TRUE;
}
