/* Test stand-in for NV Access's nvdaControllerClient.dll: silent, counts calls.
 * Built as nvdaControllerClient.nvaccess.dll into the test folder only. */
#include <windows.h>
typedef unsigned long error_status_t;
static volatile LONG g_calls;
error_status_t __stdcall nvdaController_testIfRunning(void) { InterlockedIncrement(&g_calls); return 0; }
error_status_t __stdcall nvdaController_speakText(const wchar_t *t) { (void)t; InterlockedIncrement(&g_calls); return 0; }
error_status_t __stdcall nvdaController_speakSsml(const wchar_t *s, int a, int b, unsigned char c) { (void)s; (void)a; (void)b; (void)c; InterlockedIncrement(&g_calls); return 0; }
error_status_t __stdcall nvdaController_cancelSpeech(void) { InterlockedIncrement(&g_calls); return 0; }
error_status_t __stdcall nvdaController_brailleMessage(const wchar_t *m) { (void)m; InterlockedIncrement(&g_calls); return 0; }
error_status_t __stdcall nvdaController_getProcessId(unsigned long *p) { InterlockedIncrement(&g_calls); if (p) *p = 4242; return 0; }
error_status_t __stdcall nvdaController_setOnSsmlMarkReachedCallback(void *cb) { (void)cb; InterlockedIncrement(&g_calls); return 0; }
__declspec(dllexport) LONG __stdcall stub_calls(void) { return g_calls; }
