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
    
    // Read the getters from RAM (Removed String copying)
    static const char* getDeviceName();  // Retrieves the device name from NVS.
    static const char* getServiceUUID(); // Retrieves the service UUID from NVS.
    static const char* getDataCharUUID();    // Retrieves the Data characteristic UUID from NVS.
    static const char* getControlCharUUID(); // Retrieves the Control characteristic UUID from NVS.
    static uint32_t getLoRaID();     // Retrieves the LoRa ID from NVS.

    static void setPowerProfile(PowerProfile profile); // Sets the power profile for the device (Battery Saver, Balanced, Performance).
    
    static void setUsername(const char* username); // Sets the username.
    static const char* getUsername(); // Retrieves the username saved from NVS.
    static void setColor(const char* hexColor); // Sets the user favorite color.
    static const char* getColor(); // Retrieves the favorite color saved from NVS.
private:
    // Static variables for caching
    static char cachedDeviceName[32];
    static char cachedServiceUUID[40];
    static char cachedDataUUID[40];
    static char cachedControlUUID[40];
    static char cachedUsername[32];
    static char cachedColor[10];
    static uint32_t cachedLoraID;

    static String generateUUID();       // Helper function to generate a random UUID (version 4).
    static String generateDeviceName(); // Helper function to generate a device name based on Prefix + MAC address.
    static uint32_t generateLoRaID();    // Helper function to generate a random LoRa ID.
    // Default generators for user preferences
    static String generateDefaultUsername(); 
    static String generateDefaultColor();
    static void checkIfExists(const char* key, String (*generator)()); // Checks if a key - value pair exists in NVS, if not generates and stores it.
    static void checkIfExists(const char* key, uint32_t (*generator)()); // Overloaded function for uint32_t values.
};

#endif