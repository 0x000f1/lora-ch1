#include <Arduino.h>
#include "utils/log_helper.h"
#include "components/ble.h"
#include "components/system_manager.h"
#include "components/lora.h"

#define TAG "MAIN"

void setup() {
    Serial.begin(115200);
    SystemManager::setupNVS();
    if (BLEManager::setupBLE() != 0) {
        LOG_E(TAG, "Failed to initialize BLE.");
    } else {
        LOG_I(TAG, "BLE initialized successfully.");
    }
    LoRaManager::setupLoRa();
}

void loop() {
    LoRaManager::handleFlags();
    yield(); // Allow background tasks to run
}