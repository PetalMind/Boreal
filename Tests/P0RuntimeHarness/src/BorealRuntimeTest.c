#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *kWindowClass = "BorealRuntimeTestWindow";
static const char *kWindowTitle = "Boreal Runtime Test";

static BOOL spawn_child_process(int sleep_seconds) {
    char executable[MAX_PATH];
    char command_line[MAX_PATH + 64];
    STARTUPINFOA startup = {0};
    PROCESS_INFORMATION process = {0};
    DWORD length;

    length = GetModuleFileNameA(NULL, executable, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        return FALSE;
    }
    if (snprintf(command_line, sizeof(command_line), "\"%s\" --child --sleep %d", executable, sleep_seconds) < 0) {
        return FALSE;
    }
    startup.cb = sizeof(startup);
    if (!CreateProcessA(NULL, command_line, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &process)) {
        return FALSE;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return TRUE;
}

static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
    case WM_CLOSE:
        DestroyWindow(window);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    default:
        return DefWindowProcA(window, message, wparam, lparam);
    }
}

static int parse_int(const char *flag, const char *value, int minimum, int maximum) {
    char *end = NULL;
    long parsed;

    errno = 0;
    parsed = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || parsed < minimum || parsed > maximum) {
        fprintf(stderr, "Invalid value for %s: %s (expected %d...%d)\n", flag, value, minimum, maximum);
        fflush(stderr);
        ExitProcess(64);
    }
    return (int)parsed;
}

static HWND create_test_window(HINSTANCE instance) {
    WNDCLASSEXA window_class = {0};
    HWND window;

    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = window_proc;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursor(NULL, IDC_ARROW);
    window_class.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    window_class.lpszClassName = kWindowClass;

    if (!RegisterClassExA(&window_class) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        return NULL;
    }

    window = CreateWindowExA(
        0,
        kWindowClass,
        kWindowTitle,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        520,
        220,
        NULL,
        NULL,
        instance,
        NULL
    );
    if (window == NULL) {
        return NULL;
    }

    CreateWindowExA(
        0,
        "STATIC",
        "Boreal Runtime validation is running.",
        WS_CHILD | WS_VISIBLE | SS_CENTER,
        40,
        65,
        420,
        28,
        window,
        NULL,
        instance,
        NULL
    );
    ShowWindow(window, SW_SHOW);
    UpdateWindow(window);
    return window;
}

int main(int argc, char **argv) {
    int sleep_seconds = 1;
    int spawn_child_seconds = -1;
    int exit_code = 0;
    BOOL is_child = FALSE;
    int index;
    HWND window;
    ULONGLONG deadline;
    MSG message;
    BOOL closed = FALSE;

    for (index = 1; index < argc; ++index) {
        if (strcmp(argv[index], "--sleep") == 0 && index + 1 < argc) {
            sleep_seconds = parse_int("--sleep", argv[++index], 0, 86400);
        } else if (strcmp(argv[index], "--exit-code") == 0 && index + 1 < argc) {
            exit_code = parse_int("--exit-code", argv[++index], 0, 255);
        } else if (strcmp(argv[index], "--spawn-child") == 0 && index + 1 < argc) {
            spawn_child_seconds = parse_int("--spawn-child", argv[++index], 1, 86400);
        } else if (strcmp(argv[index], "--child") == 0) {
            is_child = TRUE;
        } else {
            fprintf(stderr, "Unknown or incomplete argument: %s\n", argv[index]);
            fflush(stderr);
            return 64;
        }
    }

    window = create_test_window(GetModuleHandleA(NULL));
    if (window == NULL) {
        fprintf(stderr, "BOREAL_WINDOW_ERROR=%lu\n", (unsigned long)GetLastError());
        fflush(stderr);
        return 70;
    }

    fputs("BOREAL_STDOUT_OK\n", stdout);
    fflush(stdout);
    fputs("BOREAL_STDERR_OK\n", stderr);
    fflush(stderr);

    if (is_child) {
        fputs("BOREAL_CHILD_OK\n", stdout);
        fflush(stdout);
    } else if (spawn_child_seconds >= 0) {
        if (!spawn_child_process(spawn_child_seconds)) {
            fprintf(stderr, "BOREAL_CHILD_ERROR=%lu\n", (unsigned long)GetLastError());
            fflush(stderr);
            DestroyWindow(window);
            return 71;
        }
        fputs("BOREAL_CHILD_SPAWNED\n", stdout);
        fflush(stdout);
        DestroyWindow(window);
        return exit_code;
    }

    deadline = GetTickCount64() + ((ULONGLONG)sleep_seconds * 1000ULL);
    while (!closed && GetTickCount64() < deadline) {
        while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) {
                closed = TRUE;
                break;
            }
            TranslateMessage(&message);
            DispatchMessageA(&message);
        }
        if (!closed) {
            Sleep(10);
        }
    }

    if (!closed && IsWindow(window)) {
        DestroyWindow(window);
    }
    return exit_code;
}
