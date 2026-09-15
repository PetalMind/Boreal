#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include "blg_log.h"

#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>

namespace {

volatile LONG g_loggerState = 0;
char g_logPath[MAX_PATH] = {};
bool g_traceEnabled = false;

void initializeLogger() {
    LONG state = InterlockedCompareExchange(&g_loggerState, 1, 0);
    if (state == 1) {
        while (g_loggerState == 1) {
            Sleep(0);
        }
        return;
    }
    if (state == 2) {
        return;
    }

    char configuredPath[MAX_PATH] = {};
    DWORD configuredLength = GetEnvironmentVariableA(
        "BLG_LOG_PATH",
        configuredPath,
        static_cast<DWORD>(sizeof(configuredPath))
    );
    if (configuredLength > 0 && configuredLength < sizeof(g_logPath)) {
        lstrcpynA(g_logPath, configuredPath, sizeof(g_logPath));
    } else {
        char tempPath[MAX_PATH] = {};
        DWORD tempLength = GetTempPathA(static_cast<DWORD>(sizeof(tempPath)), tempPath);
        if (tempLength > 0 && tempLength < sizeof(tempPath)) {
            _snprintf_s(
                g_logPath,
                sizeof(g_logPath),
                _TRUNCATE,
                "%sBorealLegacyGraphics-%lu.log",
                tempPath,
                static_cast<unsigned long>(GetCurrentProcessId())
            );
        } else {
            lstrcpynA(g_logPath, "BorealLegacyGraphics.log", sizeof(g_logPath));
        }
    }

    char configuredLevel[32] = {};
    DWORD levelLength = GetEnvironmentVariableA(
        "BLG_LOG",
        configuredLevel,
        static_cast<DWORD>(sizeof(configuredLevel))
    );
    g_traceEnabled = levelLength >= 5 && _strnicmp(configuredLevel, "trace", 5) == 0;

    InterlockedExchange(&g_loggerState, 2);
}

void writeLog(const char *level, const char *format, va_list arguments) {
    initializeLogger();

    char message[2048] = {};
    _vsnprintf_s(message, sizeof(message), _TRUNCATE, format, arguments);

    char line[2304] = {};
    _snprintf_s(
        line,
        sizeof(line),
        _TRUNCATE,
        "[%lu:%lu][%s] %s\r\n",
        static_cast<unsigned long>(GetCurrentProcessId()),
        static_cast<unsigned long>(GetCurrentThreadId()),
        level,
        message
    );

    HANDLE file = CreateFileA(
        g_logPath,
        FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        nullptr
    );
    if (file != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        WriteFile(file, line, static_cast<DWORD>(lstrlenA(line)), &written, nullptr);
        CloseHandle(file);
    }
    OutputDebugStringA(line);
}

}

namespace blg {

void log(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    writeLog("info", format, arguments);
    va_end(arguments);
}

void trace(const char *format, ...) {
    // The renderer calls trace() on every legacy state and draw submission.
    // Once the logger has initialized with the default `info` level, avoid
    // repeating the initialization atomics in that hot path.
    if (g_loggerState == 2 && !g_traceEnabled) {
        return;
    }
    initializeLogger();
    if (!g_traceEnabled) {
        return;
    }

    va_list arguments;
    va_start(arguments, format);
    writeLog("trace", format, arguments);
    va_end(arguments);
}

}
