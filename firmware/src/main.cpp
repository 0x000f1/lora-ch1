#include <Arduino.h>
#include "utils/log_helper.h"
#include "components/ble.h"
#include "components/system_manager.h"
#include "components/lora.h"

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