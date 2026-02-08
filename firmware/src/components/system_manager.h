/**
 * @file system_manager.h
 * @brief System management functions, including NVS initialization and UUID generation.
 * @details This component provides auto generation of UUIDs and Device Name for BLE, and saves them in NVS.
 */

#ifndef SYSTEM_MANAGER_H
#define SYSTEM_MANAGER_H

#include <Arduino.h>

class SystemManager {
public:
    static void setupNVS();
    static String getDeviceName();
    static String getServiceUUID();
    static String getCharUUID();

private:
    static String generateUUID();
    static String generateDeviceName();
    static void checkIfExists(const char* key, String (*generator)());
};

#endif