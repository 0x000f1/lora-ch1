#include <Arduino.h>
#include "utils/log_helper.h"
#include "managers/ble/ble.h"
#include "managers/system/system_manager.h"
#include "managers/lora/lora.h"
#include "drivers/ui/haptic.h"
#include "drivers/ui/button.h"

#define TAG "MAIN"

void setup() {
    Serial.begin(115200);
    delay(3000);
    // Set the default power profile to BALANCED to able to use BLE (advertising and connection)
    SystemManager::setPowerProfile(PowerProfile::BALANCED);

    SystemManager::setupNVS();
    BLEManager::setupBLE();
    LoRaManager::setupLoRa();
    HapticManager::setupHaptic();
    ButtonManager::setupButton();
}

void loop() {
    LoRaManager::handleFlags();
    ButtonManager::handleButton();
    yield(); // Allow background tasks to run
}