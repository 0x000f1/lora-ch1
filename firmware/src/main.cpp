#include <Arduino.h>
#include "utils/log_helper.h"
#include "managers/ble/ble.h"
#include "managers/system/system_manager.h"
#include "managers/lora/lora.h"

#define TAG "MAIN"

void setup() {
    Serial.begin(115200);
    SystemManager::setupNVS();
    BLEManager::setupBLE();
    LoRaManager::setupLoRa();
}

void loop() {
    LoRaManager::handleFlags();
    yield(); // Allow background tasks to run
}