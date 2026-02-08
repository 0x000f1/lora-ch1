/**
 * @file log_helper.h
 * @brief Logging helper functions.
 * @details Consistent logging format for the project, with support different log levels (Info, Warning, Error).
 */

#ifndef LOG_HELPER_H
#define LOG_HELPER_H

#include <Arduino.h>

class Log {
public:
    static void Print(const char* level, const char* tag, const char* format, ...);

    #define LOG_I(tag, fmt, ...) Log::Print("INFO", tag, fmt, ##__VA_ARGS__)
    #define LOG_W(tag, fmt, ...) Log::Print("WARN", tag, fmt, ##__VA_ARGS__)
    #define LOG_E(tag, fmt, ...) Log::Print("ERROR", tag, fmt, ##__VA_ARGS__)
};

#endif