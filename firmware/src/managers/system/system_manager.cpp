#include "system_manager.h"
#include "utils/log_helper.h"
#include <Preferences.h>
#include <esp_mac.h>
#include <esp_random.h>

#define STORAGE_NAMESPACE "system" 
#define TAG "SYS"
#define DEVICE_NAME_PREFIX "lora-ch1"

Preferences prefs; // Global Preferences for NVS access

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

void SystemManager::checkIfExists(const char* key, String (*generator)()) {
    if (!prefs.isKey(key)) {
        String newVal = generator();
        prefs.putString(key, newVal);
        LOG_I(TAG, "%s generated: %s", key, newVal.c_str());
    } else {
        LOG_I(TAG, "%s loaded: %s", key, prefs.getString(key).c_str());
    }
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
    checkIfExists("c_uuid", generateUUID);
}

String SystemManager::getDeviceName() {
    // Return the device name stored in NVS
    return prefs.getString("device_name", "unknown-device");
}

String SystemManager::getServiceUUID() {
    // Return the service UUID stored in NVS
    return prefs.getString("s_uuid", "00000000-0000-0000-0000-000000000000");
}

String SystemManager::getCharUUID() {
    // Return the characteristic UUID stored in NVS
    return prefs.getString("c_uuid", "00000000-0000-0000-0000-000000000001");
}