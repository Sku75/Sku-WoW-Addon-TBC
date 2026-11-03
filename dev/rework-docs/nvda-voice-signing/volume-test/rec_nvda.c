/* Offline stand-in for NV Access's nvdaControllerClient.dll: silent, and
 * writes every call the bridge makes to the file named by S2SR_REC (UTF-8,
 * one line per call: "<function>\t<text>", newlines in the text as \n).
 * Built as nvdaControllerClient.dll into a test folder beside a test copy of
 * sapi2sr_engine.dll; never installed. */
#include <windows.h>
typedef unsigned long error_status_t;

static void rec(const char *fn, const wchar_t *t)
{
    wchar_t path[MAX_PATH];
    if (!GetEnvironmentVariableW(L"S2SR_REC", path, MAX_PATH)) return;
    HANDLE h = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, 0, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    DWORD n;
    WriteFile(h, fn, (DWORD)lstrlenA(fn), &n, NULL);
    if (t) {
        WriteFile(h, "\t", 1, &n, NULL);
        for (; *t; t++) {
            char buf[8];
            int len;
            if (*t == L'\n') { WriteFile(h, "\\n", 2, &n, NULL); continue; }
            if (*t == L'\r') { WriteFile(h, "\\r", 2, &n, NULL); continue; }
            len = WideCharToMultiByte(CP_UTF8, 0, t, (t[0] >= 0xD800 && t[0] < 0xDC00 && t[1]) ? 2 : 1, buf, sizeof buf, NULL, NULL);
            if (t[0] >= 0xD800 && t[0] < 0xDC00 && t[1]) t++;
            if (len > 0) WriteFile(h, buf, (DWORD)len, &n, NULL);
        }
    }
    WriteFile(h, "\n", 1, &n, NULL);
    CloseHandle(h);
}

error_status_t __stdcall nvdaController_testIfRunning(void) { return 0; }
error_status_t __stdcall nvdaController_speakText(const wchar_t *t) { rec("speakText", t); return 0; }
error_status_t __stdcall nvdaController_speakSsml(const wchar_t *s, int a, int b, unsigned char c) { (void)a; (void)b; (void)c; rec("speakSsml", s); return 0; }
error_status_t __stdcall nvdaController_cancelSpeech(void) { rec("cancelSpeech", NULL); return 0; }
error_status_t __stdcall nvdaController_brailleMessage(const wchar_t *m) { rec("brailleMessage", m); return 0; }
error_status_t __stdcall nvdaController_getProcessId(unsigned long *p) { if (p) *p = 4242; return 0; }
error_status_t __stdcall nvdaController_setOnSsmlMarkReachedCallback(void *cb) { (void)cb; return 0; }
