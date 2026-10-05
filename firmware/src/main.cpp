#include <Arduino.h>
#include "utils/log_helper.h"
#include "managers/ble/ble.h"
#include "managers/system/system_manager.h"
#include "managers/lora/lora.h"
#include "drivers/ui/haptic.h"
#include "drivers/ui/button.h"

#define TAG "MAIN"

TaskHandle_t mainTaskHandle = NULL;

void setup() {
    Serial.begin(115200);
    
    mainTaskHandle = xTaskGetCurrentTaskHandle();
    LoRaManager::setMainTaskHandle(mainTaskHandle);

    BatteryManager::setupBattery();
    // Set the default power profile to BATTERY_SAVER until button pressed
    SystemManager::setPowerProfile(PowerProfile::BATTERY_SAVER);
    SystemManager::setupNVS();
    BLEManager::setupBLE();

    int loraState = LoRaManager::setupLoRa();
    if (loraState != 0) {
        LOG_E(TAG, "LoRa setup failed: %d", loraState);
    }

    HapticManager::setupHaptic();
    ButtonManager::setupButton();
}

void handleHILCommands() {
    if (Serial.available()) {
        String cmd = Serial.readStringUntil('\n');
        cmd.trim();
        
        if (cmd == "PING") {
            Serial.println("PONG");
        }
        if (cmd == "TEST_HAP") {
            LOG_I(TAG, "HIL: Haptic test triggered");
            HapticManager::playEffect(7);
            Serial.println("UART:haptest_ok");
        } 
        else if (cmd == "TEST_ADV") {
            LOG_I(TAG, "HIL: BLE Advertising triggered");
            BLEManager::startPairingMode();
            Serial.println("UART:advtest_ok");
        } 
        else if (cmd == "TEST_TX") {
            LOG_I(TAG, "HIL: LoRa TX triggered");
            uint8_t payload[] = "HIL_STRESS_TEST";
            LoRaManager::queueMessage(payload, sizeof(payload), BROADCAST_ADDRESS, 1, 1);
            Serial.println("UART:txtest_ok");
        } 
        else if (cmd.startsWith("SET_PWR;")) {
            int pwr = cmd.substring(8).toInt();
            SystemManager::setPowerProfile((PowerProfile)pwr);
            Serial.println("UART:pwr_ok");
        }
        else if (cmd == "TEST_BAT") {
            LOG_I("MAIN", "HIL: Forcing Low Battery Check");
            BatteryManager::checkLowBattery();
            Serial.println("UART:bat_check_done");
        }
        else if (cmd == "GET_BAT") {
            uint8_t batLevel = BatteryManager::getBatteryPercentage();
            Serial.printf("UART:BAT;%d\n", batLevel);
        }
    }
}

void loop() {
    BLEManager::handleFlags();
    LoRaManager::handleFlags();
    ButtonManager::handleButton();
    // handleHILCommands();
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(10));
}