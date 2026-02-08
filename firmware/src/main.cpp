#include <Arduino.h>
#include "utils/log_helper.h"
#include "components/ble.h"
#include "components/system_manager.h"

#define TAG "MAIN"

void setup() {
    Serial.begin(115200);
    SystemManager::setupNVS();
    if (BLEManager::setupBLE() != 0) {
        LOG_E(TAG, "Failed to initialize BLE.");
    } else {
        LOG_I(TAG, "BLE initialized successfully.");
    }
}

void loop() {
    if (Serial.available() > 0) {
        String input = Serial.readStringUntil('\n');
        input.trim();

        if (input.length() > 0) {
            BLEManager::pushMessage(input.c_str());
        }
    }

    delay(20);
}