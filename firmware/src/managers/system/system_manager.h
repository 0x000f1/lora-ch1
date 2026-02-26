/**
 * @file system_manager.h
 * @brief System management functions, including NVS initialization and UUID generation.
 * @details This component provides auto generation of UUIDs and Device Name for BLE, and saves them in NVS.
 */

#ifndef SYSTEM_MANAGER_H
#define SYSTEM_MANAGER_H

#include <Arduino.h>
#include "drivers/power/battery.h"

class SystemManager {
public:
    static void setupNVS();         // Initializes NVS and generates/checks device name and UUIDs. Should be called at startup.
    static String getDeviceName();  // Retrieves the device name from NVS.
    static String getServiceUUID(); // Retrieves the service UUID from NVS.
    static String getCharUUID();    // Retrieves the characteristic UUID from NVS.
    static uint32_t getLoRaID();     // Retrieves the LoRa ID from NVS.
    static void setPowerProfile(PowerProfile profile); // Sets the power profile for the device (Battery Saver, Balanced, Performance).
private:
    static String generateUUID();       // Helper function to generate a random UUID (version 4).
    static String generateDeviceName(); // Helper function to generate a device name based on Prefix + MAC address.
    static uint32_t generateLoRaID();    // Helper function to generate a random LoRa ID.
    static void checkIfExists(const char* key, String (*generator)()); // Checks if a key - value pair exists in NVS, if not generates and stores it.
    static void checkIfExists(const char* key, uint32_t (*generator)()); // Overloaded function for uint32_t values.
};

#endif