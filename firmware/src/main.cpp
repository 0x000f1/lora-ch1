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
    // Set the default power profile to BATTERY_SAVER until button pressed
    SystemManager::setPowerProfile(PowerProfile::BATTERY_SAVER);
    SystemManager::setupNVS();
    BLEManager::setupBLE();
    LoRaManager::setupLoRa();
    HapticManager::setupHaptic();
    ButtonManager::setupButton();
}

void loop() {
    BLEManager::handleFlags();
    LoRaManager::handleFlags();
    ButtonManager::handleButton();
    vTaskDelay(pdMS_TO_TICKS(10));
}