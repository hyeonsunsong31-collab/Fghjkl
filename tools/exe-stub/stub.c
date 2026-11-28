/*
 * Jarvis package launcher for Windows (x64).
 *
 * Jarvis appends a payload to this small program to make a real Windows .exe out of
 * any files (a web game, a document, settings): running the .exe restores the files
 * and opens the main one with its default app. No C runtime, no installer.
 *
 * Payload layout (all integers little-endian), appended after the program:
 *   header:  "JRVSPKG1" u32 version=1, u32 flags, u32 count,
 *            u32 nameLen, name (UTF-8), u32 openLen, open (UTF-8, relative path)
 *   entries: count x { u32 pathLen, path (UTF-8, '/' separators), u64 size, data }
 *   footer:  u64 offset of the header, "JRVSEND1"
 * flags: 1 = open `open` after extracting, 2 = extract next to the .exe
 *        (otherwise to %TEMP%\JarvisApps\<name>).
 * Environment: JARVIS_QUIET=1 shows no dialogs and opens nothing (automated tests);
 *              the exit code then reports errors.
 *
 * Build (see build.sh): x86_64-w64-mingw32-gcc -Os -nostdlib ... -lkernel32 -lshell32 -luser32
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>

#define PATHCAP 2048

static HANDLE self;
static BOOL quiet;
static unsigned char io[65536];
static WCHAR exePath[PATHCAP], dest[PATHCAP], target[PATHCAP], openPath[PATHCAP], wide[PATHCAP], env[8];
static char utf8[PATHCAP];

void *memset(void *d, int c, SIZE_T n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, SIZE_T n) { unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }

static void fail(const WCHAR *msg, UINT code) {
    if (!quiet) MessageBoxW(NULL, msg, L"Jarvis package", MB_ICONERROR | MB_OK);
    ExitProcess(code);
}

static BOOL readExact(void *buf, DWORD n) {
    DWORD got = 0;
    return ReadFile(self, buf, n, &got, NULL) && got == n;
}

static BOOL seekTo(ULONGLONG offset) {
    LARGE_INTEGER li;
    li.QuadPart = (LONGLONG)offset;
    return SetFilePointerEx(self, li, NULL, FILE_BEGIN);
}

static DWORD readU32(void) {
    unsigned char b[4];
    if (!readExact(b, 4)) fail(L"The package is damaged (truncated).", 3);
    return (DWORD)b[0] | ((DWORD)b[1] << 8) | ((DWORD)b[2] << 16) | ((DWORD)b[3] << 24);
}

static ULONGLONG readU64(void) {
    ULONGLONG lo = readU32();
    ULONGLONG hi = readU32();
    return lo | (hi << 32);
}

static int length(const WCHAR *s) { int n = 0; while (s[n]) n++; return n; }

static void append(WCHAR *to, const WCHAR *s) {
    int n = length(to), i = 0;
    while (s[i] && n < PATHCAP - 1) to[n++] = s[i++];
    to[n] = 0;
}

static void copyW(WCHAR *to, const WCHAR *s) { to[0] = 0; append(to, s); }

/* Read a UTF-8 string of n bytes from the package into `wide`; reject unsafe paths. */
static BOOL readName(DWORD n, BOOL isPath) {
    if (n >= PATHCAP) fail(L"The package is damaged (name too long).", 3);
    if (n && !readExact(utf8, n)) fail(L"The package is damaged (truncated name).", 3);
    utf8[n] = 0;
    int m = n ? MultiByteToWideChar(CP_UTF8, 0, utf8, (int)n, wide, PATHCAP - 1) : 0;
    wide[m] = 0;
    if (!isPath) return TRUE;
    if (m == 0 || wide[0] == L'/' || wide[0] == L'\\' || (m > 1 && wide[1] == L':')) return FALSE;
    for (int i = 0; i < m; i++) {
        if (wide[i] == L'/') wide[i] = L'\\';
        if (wide[i] == L'.' && wide[i + 1] == L'.' && (i == 0 || wide[i - 1] == L'\\') && (wide[i + 2] == L'\\' || wide[i + 2] == 0)) return FALSE;
    }
    return TRUE;
}

/* Create every folder on the way to a file path. */
static void makeParents(WCHAR *path) {
    for (WCHAR *p = path + 3; *p; p++) {
        if (*p == L'\\') {
            *p = 0;
            CreateDirectoryW(path, NULL);
            *p = L'\\';
        }
    }
}

void __stdcall start(void) {
    quiet = GetEnvironmentVariableW(L"JARVIS_QUIET", env, 8) > 0;
    DWORD got = GetModuleFileNameW(NULL, exePath, PATHCAP);
    if (got == 0 || got >= PATHCAP) fail(L"Can't find the package file.", 2);
    self = CreateFileW(exePath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (self == INVALID_HANDLE_VALUE) fail(L"Can't read the package file.", 2);
    LARGE_INTEGER size;
    if (!GetFileSizeEx(self, &size) || size.QuadPart < 64) fail(L"The package is empty.", 3);

    unsigned char magic[8];
    if (!seekTo((ULONGLONG)size.QuadPart - 16)) fail(L"The package is damaged.", 3);
    ULONGLONG headerAt = readU64();
    if (!readExact(magic, 8) || magic[0] != 'J' || magic[1] != 'R' || magic[2] != 'V' || magic[3] != 'S' ||
        magic[4] != 'E' || magic[5] != 'N' || magic[6] != 'D' || magic[7] != '1')
        fail(L"This launcher has no package attached.", 4);
    if (headerAt >= (ULONGLONG)size.QuadPart || !seekTo(headerAt)) fail(L"The package is damaged (offset).", 3);
    if (!readExact(magic, 8) || magic[0] != 'J' || magic[7] != '1') fail(L"The package is damaged (header).", 3);
    DWORD version = readU32();
    if (version != 1) fail(L"This package needs a newer launcher.", 5);
    DWORD flags = readU32();
    DWORD count = readU32();

    /* Destination folder. */
    readName(readU32(), FALSE);
    if (flags & 2) {
        copyW(dest, exePath);
        int i = length(dest);
        while (i > 0 && dest[i - 1] != L'\\') i--;
        dest[i] = 0;
    } else {
        if (!GetTempPathW(PATHCAP - 64, dest)) fail(L"No temporary folder.", 6);
        append(dest, L"JarvisApps\\");
        CreateDirectoryW(dest, NULL);
    }
    if (wide[0] == 0) copyW(wide, L"package");
    for (int i = 0; wide[i]; i++) if (wide[i] == L'\\' || wide[i] == L'/' || wide[i] == L':') wide[i] = L'_';
    append(dest, wide);
    CreateDirectoryW(dest, NULL);
    append(dest, L"\\");

    BOOL hasOpen = readName(readU32(), TRUE);
    openPath[0] = 0;
    if (hasOpen && wide[0]) { copyW(openPath, dest); append(openPath, wide); }

    for (DWORD e = 0; e < count; e++) {
        BOOL safe = readName(readU32(), TRUE);
        ULONGLONG remaining = readU64();
        HANDLE out = INVALID_HANDLE_VALUE;
        if (safe) {
            copyW(target, dest);
            append(target, wide);
            makeParents(target);
            out = CreateFileW(target, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
            if (out == INVALID_HANDLE_VALUE) fail(L"Can't write a file (is it open in another program?).", 7);
        }
        while (remaining > 0) {
            DWORD chunk = remaining > sizeof(io) ? (DWORD)sizeof(io) : (DWORD)remaining;
            if (!readExact(io, chunk)) fail(L"The package is damaged (truncated data).", 3);
            if (out != INVALID_HANDLE_VALUE) {
                DWORD written = 0;
                if (!WriteFile(out, io, chunk, &written, NULL) || written != chunk) fail(L"The disk is full or not writable.", 8);
            }
            remaining -= chunk;
        }
        if (out != INVALID_HANDLE_VALUE) CloseHandle(out);
    }
    CloseHandle(self);

    if ((flags & 1) && openPath[0] && !quiet) {
        HINSTANCE r = ShellExecuteW(NULL, L"open", openPath, NULL, dest, SW_SHOWNORMAL);
        if ((INT_PTR)r <= 32) {
            /* No app for this file type: show the folder instead. */
            ShellExecuteW(NULL, L"open", dest, NULL, NULL, SW_SHOWNORMAL);
        }
    } else if (!quiet && !(flags & 1)) {
        MessageBoxW(NULL, dest, L"Files restored to", MB_ICONINFORMATION | MB_OK);
    }
    ExitProcess(0);
}
