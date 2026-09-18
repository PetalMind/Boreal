#pragma once

#include <cstdarg>
#include <fstream>
#include <string>

class Logger {
public:
    void Initialize(const std::string& path);
    void Log(const char* format, ...);
    void Error(const char* format, ...);
    bool IsOpen() const { return m_file.is_open(); }

private:
    void Write(const char* level, const char* format, va_list arguments);
    std::ofstream m_file;
};
