#include "system_manager.h"
#include "utils/log_helper.h"
#include "drivers/power/battery.h"
#include "managers/lora/lora.h"
#include <Preferences.h>
#include <esp_mac.h>
#include <esp_random.h>

#define STORAGE_NAMESPACE "system" 
#define TAG "SYS"
#define DEVICE_NAME_PREFIX "lora-ch1"

Preferences prefs; // Global Preferences for NVS access

// Cache initialization
char SystemManager::cachedDeviceName[32] = {0};
char SystemManager::cachedServiceUUID[40] = {0};
char SystemManager::cachedDataUUID[40] = {0};
char SystemManager::cachedControlUUID[40] = {0};
char SystemManager::cachedUsername[32] = {0};
char SystemManager::cachedColor[10] = {0};
uint32_t SystemManager::cachedLoraID = 0;

String SystemManager::generateUUID() {
    String uuid = "";
    
    for (int i = 0; i < 16; i++) {
        uint8_t b = (uint8_t)esp_random();  // Generate a random byte (0-255)
        if (i == 6) b = (b & 0x0F) | 0x40;  // Fixed bits for version 4 UUID (0100xxxx)
        if (i == 8) b = (b & 0x3F) | 0x80;  // Fixed bits for variant (10xxxxxx)

        if (b < 16) uuid += "0";            // Leading zero for <16 to maintain 2 hex digits
        uuid += String(b, HEX);             // Convert to HEX and append to UUID string

        if (i == 3 || i == 5 || i == 7 || i == 9) uuid += "-"; // Add - at the fix points
    }
    return uuid;
}

String SystemManager::generateDeviceName() {
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    char buf[20];
    sprintf(buf, "%s-%02X%02X", DEVICE_NAME_PREFIX, mac[4], mac[5]);
    return String(buf);
}

uint32_t SystemManager::generateLoRaID() {
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    // Last 4 bytes of the MAC are used to generate the LoRa ID
    uint32_t id = (mac[2] << 24) | (mac[3] << 16) | (mac[4] << 8) | mac[5];
    return id;
}

String SystemManager::generateDefaultUsername() {
    return String("Guest");
}

String SystemManager::generateDefaultColor() {
    return String("0088FF"); // Light blue color
}

void SystemManager::checkIfExists(const char* key, String (*generator)()) {
    if (!prefs.isKey(key)) {
        String newVal = generator();
        prefs.putString(key, newVal);
        LOG_I(TAG, "%s generated: %s", key, newVal.c_str());
    } else {
        LOG_I(TAG, "%s loaded: %s", key, prefs.getString(key).c_str());
    }
}

void SystemManager::checkIfExists(const char* key, uint32_t (*generator)()) {
    if (!prefs.isKey(key)) {
        uint32_t newVal = generator();
        prefs.putUInt(key, newVal);
        LOG_I(TAG, "%s generated: 0x%08X", key, newVal);
    } else {
        LOG_I(TAG, "%s loaded: 0x%08X", key, prefs.getUInt(key));
    }
}

void SystemManager::setPowerProfile(PowerProfile profile) {
    BatteryManager::setPowerProfile(profile);

    // Heartbeat interval based on power profile
    uint16_t heartbeatInterval = 30; // Default to 30 seconds for BALANCED
    switch (profile) {
        case PowerProfile::BATTERY_SAVER:   heartbeatInterval = 60; break;
        case PowerProfile::BALANCED:        heartbeatInterval = 30; break;
        case PowerProfile::PERFORMANCE:     heartbeatInterval = 15; break;
    }
    LoRaManager::startHeartbeat(heartbeatInterval);
    LOG_I(TAG, "Heartbeat interval set to %d seconds", heartbeatInterval);
}

/** 
 * @brief Initializes NVS and generates/stores device name and UUIDs if they don't exist. (First boot)
 * @details This function checks if the device name, service UUID, and characteristic UUID are already stored in NVS.
 * If not, it generates them, stores them in NVS, and logs. If they already exist, it simply loads and logs them.
*/
void SystemManager::setupNVS() {
    prefs.begin(STORAGE_NAMESPACE, false);

    checkIfExists("device_name", generateDeviceName);
    checkIfExists("s_uuid", generateUUID);
    checkIfExists("c_data_uuid", generateUUID);
    checkIfExists("c_control_uuid", generateUUID);
    checkIfExists("lora_id", generateLoRaID);
    checkIfExists("username", generateDefaultUsername);
    checkIfExists("color", generateDefaultColor);

    // Cache populating with error handling
    strncpy(cachedDeviceName, prefs.getString("device_name", "unknown-device").c_str(), sizeof(cachedDeviceName) - 1);
    strncpy(cachedServiceUUID, prefs.getString("s_uuid", "00000000-0000-0000-0000-000000000000").c_str(), sizeof(cachedServiceUUID) - 1);
    strncpy(cachedDataUUID, prefs.getString("c_data_uuid", "00000000-0000-0000-0000-000000000001").c_str(), sizeof(cachedDataUUID) - 1);
    strncpy(cachedControlUUID, prefs.getString("c_control_uuid", "00000000-0000-0000-0000-000000000002").c_str(), sizeof(cachedControlUUID) - 1);
    strncpy(cachedUsername, prefs.getString("username", "Guest").c_str(), sizeof(cachedUsername) - 1);
    strncpy(cachedColor, prefs.getString("color", "0088FF").c_str(), sizeof(cachedColor) - 1);
    cachedLoraID = prefs.getUInt("lora_id", 0);
}

// Getter methods from RAM with empty value handling
const char* SystemManager::getDeviceName() {
    // Return the device name stored in CACHE
    return (cachedDeviceName[0] == '\0') ? "unknown-device" : cachedDeviceName;
}

const char* SystemManager::getServiceUUID() {
    // Return the service UUID stored in CACHE
    return cachedServiceUUID;
}

const char* SystemManager::getDataCharUUID() {
    // Return the characteristic UUID stored in CACHE
    return cachedDataUUID;
}

const char* SystemManager::getControlCharUUID() {
    // Return the control characteristic UUID stored in CACHE
    return cachedControlUUID;
}

uint32_t SystemManager::getLoRaID() {
    // Return the LoRa ID stored in CACHE
    return cachedLoraID;
}

void SystemManager::setUsername(const char* username) {
    String safeName = String(username);
    safeName.trim(); // Trim the unnecessary characters
    
    if (safeName.length() == 0) safeName = "Guest"; // If input is none, set back to default
    
    prefs.putString("username", safeName);
    strncpy(cachedUsername, safeName.c_str(), sizeof(cachedUsername) - 1);
    LOG_I(TAG, "Username updated in cache: %s", cachedUsername);
}

const char* SystemManager::getUsername() {
    // Return the saved username, on NaN return Guest
    return (cachedUsername[0] == '\0') ? "Guest" : cachedUsername;
}

void SystemManager::setColor(const char* hexColor) {
    String safeColor = String(hexColor);
    safeColor.trim();
    
    if (safeColor.length() != 6) safeColor = "0088FF";
    
    prefs.putString("color", safeColor);
    strncpy(cachedColor, safeColor.c_str(), sizeof(cachedColor) - 1);
    LOG_I(TAG, "Color updated in cache: %s", cachedColor);
}

const char* SystemManager::getColor() {
    // Return the saved color, if NaN return 0088FF
    return (cachedColor[0] == '\0') ? "0088FF" : cachedColor;
}