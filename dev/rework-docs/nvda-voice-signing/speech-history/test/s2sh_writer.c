/* s2sh_writer <dir> <tag> <count> [long] - load <dir>\nvdaControllerClient.dll
 * (the proxy) and speak "<tag> <n>" count times; with "long" also one text of
 * 5000 characters and one SSML string. Prints the forwarded results and the
 * stub's call count (proves every call reached the "real" DLL).
 * Environment S2SH_TEST_WANT=1: the writer asks for its own texts first (the
 * request a reader normally makes, s2sh_shared.h); without it nothing of
 * this writer may appear in the ring. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include "../s2sh_shared.h"
typedef unsigned long (__stdcall *FnText)(const wchar_t *);
typedef unsigned long (__stdcall *FnSsml)(const wchar_t *, int, int, unsigned char);
typedef unsigned long (__stdcall *FnPid)(unsigned long *);
typedef LONG (__stdcall *FnCalls)(void);

int wmain(int argc, wchar_t **argv)
{
    WCHAR path[MAX_PATH], text[64];
    HMODULE m, stub;
    FnText speak; FnSsml ssml; FnPid pid;
    int count, i, bad = 0;
    unsigned long p = 0;
    if (argc < 4) return 9;
    count = _wtoi(argv[3]);
    if (GetEnvironmentVariableW(L"S2SH_TEST_WANT", text, 64) && text[0] == L'1') {
        swprintf(path, MAX_PATH, L"%s%lu", S2SH_WANT_PREFIX, GetCurrentProcessId());
        if (!CreateEventW(NULL, TRUE, FALSE, path)) { printf("want failed %lu\n", GetLastError()); return 1; }
    }
    swprintf(path, MAX_PATH, L"%s\\nvdaControllerClient.dll", argv[1]);
    m = LoadLibraryW(path);
    if (!m) { printf("load failed %lu\n", GetLastError()); return 1; }
    speak = (FnText)GetProcAddress(m, "nvdaController_speakText");
    ssml = (FnSsml)GetProcAddress(m, "nvdaController_speakSsml");
    pid = (FnPid)GetProcAddress(m, "nvdaController_getProcessId");
    for (i = 1; i <= count; i++) {
        swprintf(text, 64, L"%s %d", argv[2], i);
        if (speak(text) != 0) bad++;
    }
    if (argc > 4 && !wcscmp(argv[4], L"long")) {
        WCHAR *big = (WCHAR *)malloc(5001 * sizeof(WCHAR));
        for (i = 0; i < 5000; i++) big[i] = (WCHAR)(L'a' + i % 26);
        big[5000] = 0;
        if (speak(big) != 0) bad++;
        if (ssml(L"<speak>Hallo <mark name=\"x\"/>Welt äöü</speak>", 0, 1, 0) != 0) bad++;
    }
    if (pid(&p) != 0 || p != 4242) bad++;
    swprintf(path, MAX_PATH, L"%s\\nvdaControllerClient.nvaccess.dll", argv[1]);
    stub = GetModuleHandleW(path);
    printf("pid %lu bad %d stubcalls %ld\n", GetCurrentProcessId(), bad,
        stub ? ((FnCalls)GetProcAddress(stub, "stub_calls"))() : -1L);
    Sleep(argc > 5 ? _wtoi(argv[5]) : 0);   /* keep the ring alive for a reader */
    return bad;
}
