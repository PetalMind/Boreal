#include "Logger.h"

#include <cstdarg>
#include <cstdio>
#include <ctime>

void Logger::Initialize(const std::string& path) {
    m_file.open(path, std::ios::out | std::ios::app);
}

void Logger::Log(const char* format, ...) {
    va_list arguments;
    va_start(arguments, format);
    Write("INFO", format, arguments);
    va_end(arguments);
}

void Logger::Error(const char* format, ...) {
    va_list arguments;
    va_start(arguments, format);
    Write("ERROR", format, arguments);
    va_end(arguments);
}

void Logger::Write(const char* level, const char* format, va_list arguments) {
    if (!m_file.is_open()) {
        return;
    }

    char message[1024]{};
    std::vsnprintf(message, sizeof(message), format, arguments);

    std::time_t now = std::time(nullptr);
    std::tm localTime{};
#if defined(_WIN32)
    localtime_s(&localTime, &now);
#else
    localTime = *std::localtime(&now);
#endif

    char timestamp[32]{};
    std::strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", &localTime);
    m_file << '[' << timestamp << "] [" << level << "] " << message << '\n';
    m_file.flush();
}

