#include "log_helper.h"
#include <stdarg.h>

void Log::Print(const char* level, const char* tag, const char* format, ...) {
    char buffer[256];
    
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args); // Generate the formatted string with variable arguments
    va_end(args);

    Serial.printf("[%s][%s] %s\n", level, tag, buffer); // Print the log message to Serial with the specified format
}