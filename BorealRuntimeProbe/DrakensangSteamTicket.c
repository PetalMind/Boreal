/* Drakensang's 32-bit Steam API keeps the confirmed ticket alive until the
   native game controller finishes. Ticket bytes go only to its private pipe. */
#include <windows.h>
#include <stdint.h>
#include <stdio.h>

typedef struct { int user, id; unsigned char *data; int size; } Callback;
typedef int (__cdecl *Init)(void);
typedef void *(__cdecl *User)(void);
typedef uint32_t (__cdecl *GetTicket)(void *, void *, int, uint32_t *, void *);
typedef int (__cdecl *GetPipe)(void);
typedef void (__cdecl *DispatchInit)(void);
typedef void (__cdecl *RunFrame)(int);
typedef int (__cdecl *GetCallback)(int, Callback *);
typedef void (__cdecl *FreeCallback)(int);

int wmain(int argc, wchar_t **argv) {
    if (argc != 3) return 1;
    HMODULE api = LoadLibraryW(argv[1]);
    if (!api) return 2;
    Init init = (Init)(void *)GetProcAddress(api, "SteamAPI_Init");
    User user = (User)(void *)GetProcAddress(api, "SteamAPI_SteamUser_v021");
    GetTicket get_ticket = (GetTicket)(void *)GetProcAddress(api, "SteamAPI_ISteamUser_GetAuthSessionTicket");
    GetPipe get_pipe = (GetPipe)(void *)GetProcAddress(api, "SteamAPI_GetHSteamPipe");
    DispatchInit dispatch = (DispatchInit)(void *)GetProcAddress(api, "SteamAPI_ManualDispatch_Init");
    RunFrame run = (RunFrame)(void *)GetProcAddress(api, "SteamAPI_ManualDispatch_RunFrame");
    GetCallback next = (GetCallback)(void *)GetProcAddress(api, "SteamAPI_ManualDispatch_GetNextCallback");
    FreeCallback release = (FreeCallback)(void *)GetProcAddress(api, "SteamAPI_ManualDispatch_FreeLastCallback");
    if (!init || !user || !get_ticket || !get_pipe || !dispatch || !run || !next || !release) return 3;
    if (!init()) return 4;
    dispatch();
    void *steam_user = user();
    if (!steam_user) return 5;
    unsigned char ticket[4096]; uint32_t length = 0;
    uint32_t handle = get_ticket(steam_user, ticket, sizeof(ticket), &length, NULL);
    if (!handle || !length || length > sizeof(ticket)) return 6;
    int pipe = get_pipe(), confirmed = 0;
    ULONGLONG deadline = GetTickCount64() + 15000;
    while (GetTickCount64() < deadline && !confirmed) {
        run(pipe); Callback callback;
        while (next(pipe, &callback)) {
            if (callback.id == 163 && callback.size >= 8) {
                uint32_t *payload = (uint32_t *)callback.data;
                fprintf(stderr, "Steam ticket confirmation result: %lu\n", (unsigned long)payload[1]);
                if (payload[0] == handle && payload[1] == 1) confirmed = 1;
            }
            release(pipe);
        }
        Sleep(50);
    }
    if (!confirmed) return 7;
    DWORD written = 0;
    HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    if (!WriteFile(output, &length, sizeof(length), &written, NULL) || written != sizeof(length)) return 8;
    if (!WriteFile(output, ticket, length, &written, NULL) || written != length) return 9;
    SecureZeroMemory(ticket, sizeof(ticket));
    CloseHandle(output);
    /* Avoid the Wine WoW64 callback/heap teardown hang. Steam releases this
       process's temporary ticket when it disconnects. No stored token changes. */
    deadline = GetTickCount64() + 10ULL * 60 * 60 * 1000;
    while (GetTickCount64() < deadline && GetFileAttributesW(argv[2]) == INVALID_FILE_ATTRIBUTES) Sleep(500);
    TerminateProcess(GetCurrentProcess(), 0);
    return 0;
}
