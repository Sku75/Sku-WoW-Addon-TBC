/* SAPI2SR speech history: the shared-memory layout.
 *
 * Every process that speaks through the SAPI2SR bridge loads the bridge's
 * nvdaControllerClient.dll. Ours forwards each call to NV Access's original
 * (nvdaControllerClient.nvaccess.dll) and also appends the text to this ring,
 * so any program in the same Windows session can read what was spoken, in
 * order, with the process that spoke it.
 *
 * Reading: open the mapping and the lock (both names below), take the lock,
 * copy every entry whose seq is greater than the last seq you saw, release.
 * Entry n lives at entries[(seq - 1) % S2SH_ENTRIES]; an entry with seq 0 is
 * empty (or being written). header.lastSeq is the newest seq written.
 * Nothing is ever written to disk; the ring disappears when the last process
 * holding it closes. Turn publishing off with
 * %LOCALAPPDATA%\SAPI2SR\SpeechHistory.ini:  [SpeechHistory]  Publish=0
 */
#ifndef S2SH_SHARED_H
#define S2SH_SHARED_H

#include <windows.h>

#define S2SH_MAP_NAME   L"Local\\SAPI2SR.SpeechHistory.1"
#define S2SH_LOCK_NAME  L"Local\\SAPI2SR.SpeechHistory.1.Lock"
#define S2SH_MAGIC      0x48533253u   /* "S2SH" */
#define S2SH_VERSION    1u
#define S2SH_ENTRIES    64u
#define S2SH_CHARS      4000u         /* longer texts are cut, truncated = 1 */

#define S2SH_KIND_TEXT  1u            /* nvdaController_speakText */
#define S2SH_KIND_SSML  2u            /* nvdaController_speakSsml, raw markup */

typedef struct S2shEntry {
    ULONGLONG seq;                    /* 0 = empty or being written */
    ULONGLONG time;                   /* FILETIME, UTC */
    DWORD     pid;                    /* process that spoke */
    DWORD     kind;                   /* S2SH_KIND_* */
    DWORD     length;                 /* characters in text, <= S2SH_CHARS */
    DWORD     truncated;              /* 1 when the text was longer */
    WCHAR     text[S2SH_CHARS + 4];   /* NUL-terminated; +4 keeps 8-byte size */
} S2shEntry;

typedef struct S2shMap {
    DWORD     magic;                  /* S2SH_MAGIC once initialised */
    DWORD     version;                /* S2SH_VERSION */
    DWORD     entryCount;             /* S2SH_ENTRIES */
    DWORD     entryChars;             /* S2SH_CHARS */
    DWORD     headerSize;             /* offsetof(S2shMap, entries) */
    DWORD     entrySize;              /* sizeof(S2shEntry) */
    ULONGLONG lastSeq;                /* newest seq written, 0 = none */
    S2shEntry entries[S2SH_ENTRIES];
} S2shMap;

/* Fixed offsets, so readers in other languages can rely on them. */
typedef char s2sh_entry_size[(sizeof(S2shEntry) == 8040) ? 1 : -1];
typedef char s2sh_header_size[(sizeof(S2shMap) == 32 + 64 * 8040) ? 1 : -1];

#endif
