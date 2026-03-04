#include <Arduino.h>
#include "utils/log_helper.h"
#include "managers/ble/ble.h"
#include "managers/system/system_manager.h"
#include "managers/lora/lora.h"
#include "drivers/ui/haptic.h"

#define TAG "MAIN"

void setup() {
    // Set the default power profile to BALANCED to able to use BLE (advertising and connection)
    SystemManager::setPowerProfile(PowerProfile::BALANCED);
    
    Serial.begin(115200);
    SystemManager::setupNVS();
    BLEManager::setupBLE();
    LoRaManager::setupLoRa();
    HapticManager::setupHaptic();
}

void loop() {
    LoRaManager::handleFlags();
    yield(); // Allow background tasks to run
}