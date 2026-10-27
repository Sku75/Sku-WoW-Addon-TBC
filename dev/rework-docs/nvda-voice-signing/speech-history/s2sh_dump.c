/* s2sh_dump [sinceSeq] - print the speech history entries newer than
 * sinceSeq (default 0 = all), oldest first, one per line as UTF-8:
 *   seq<TAB>pid<TAB>kind<TAB>truncated<TAB>length<TAB>text
 * First line: "lastSeq<TAB>n" or "none" when no bridge process holds the ring.
 * Also the reference reader for other programs: lock, copy, release. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include "s2sh_shared.h"

static void PutUtf8(const WCHAR *w)
{
    char buf[S2SH_CHARS * 4 + 8];
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, buf, sizeof(buf), NULL, NULL);
    if (n > 0)
        fwrite(buf, 1, n - 1, stdout);
}

int wmain(int argc, wchar_t **argv)
{
    ULONGLONG since = argc > 1 ? _wcstoui64(argv[1], NULL, 10) : 0;
    HANDLE map = OpenFileMappingW(FILE_MAP_READ, FALSE, S2SH_MAP_NAME);
    DWORD mapErr = GetLastError();
    HANDLE lock = OpenMutexW(SYNCHRONIZE, FALSE, S2SH_LOCK_NAME);
    DWORD lockErr = GetLastError();
    S2shMap *ring, *copy;
    ULONGLONG seq, first;
    DWORD w;
    if (!map || !lock) {
        printf("none\t%lu\t%lu\n", map ? 0 : mapErr, lock ? 0 : lockErr);
        return 1;
    }
    ring = (S2shMap *)MapViewOfFile(map, FILE_MAP_READ, 0, 0, sizeof(S2shMap));
    copy = (S2shMap *)malloc(sizeof(S2shMap));
    if (!ring || !copy)
        return 2;
    w = WaitForSingleObject(lock, 1000);
    if (w != WAIT_OBJECT_0 && w != WAIT_ABANDONED)
        return 3;
    CopyMemory(copy, ring, sizeof(S2shMap));
    ReleaseMutex(lock);
    if (copy->magic != S2SH_MAGIC) {
        printf("empty\n");
        return 0;
    }
    printf("lastSeq\t%llu\n", copy->lastSeq);
    first = since + 1;
    if (copy->lastSeq > S2SH_ENTRIES && first < copy->lastSeq - S2SH_ENTRIES + 1)
        first = copy->lastSeq - S2SH_ENTRIES + 1;   /* older ones are overwritten */
    for (seq = first; seq <= copy->lastSeq; seq++) {
        S2shEntry *e = &copy->entries[(seq - 1) % S2SH_ENTRIES];
        if (e->seq != seq)
            continue;
        printf("%llu\t%lu\t%lu\t%lu\t%lu\t", e->seq, e->pid, e->kind, e->truncated, e->length);
        PutUtf8(e->text);
        printf("\n");
    }
    return 0;
}
