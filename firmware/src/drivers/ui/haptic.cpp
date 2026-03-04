#include "haptic.h"
#include <Wire.h>
#include "utils/log_helper.h"

#define TAG "HAPTIC"

#define HAPTIC_EN_PIN  21
#define HAPTIC_SDA_PIN 8
#define HAPTIC_SCL_PIN 9

SensorDRV2605 HapticManager::drv;
TimerHandle_t HapticManager::powerOffTimer = nullptr;

int HapticManager::setupHaptic() {
    LOG_I(TAG, "Initializing DRV2605...");

    // Set EN pin default to LOW
    pinMode(HAPTIC_EN_PIN, OUTPUT);
    digitalWrite(HAPTIC_EN_PIN, LOW);

    Wire.begin(HAPTIC_SDA_PIN, HAPTIC_SCL_PIN); // Start the I2C bus on the init progress

    powerOffTimer = xTimerCreate("hapticOffTimer", pdMS_TO_TICKS(500), pdFALSE, nullptr, powerOffTimerCallback);

    return 0;
}

void HapticManager::playEffect(uint8_t effectId) {
    digitalWrite(HAPTIC_EN_PIN, HIGH); // Turn on the chip
    vTaskDelay(pdMS_TO_TICKS(2)); // Wait 2 ms to wakeup (250us should enough)

    if (!drv.begin(Wire)) {
        LOG_E(TAG, "DRV2605 init failed!");
        digitalWrite(HAPTIC_EN_PIN, LOW);
        return;
    }
    drv.selectLibrary(1);
    drv.setMode(SensorDRV2605::MODE_INTTRIG);

    drv.setWaveform(0, effectId); // Load the effect into 'buffer' at position 0
    drv.setWaveform(1, 0); // Sequence end marker (0) at position 1
    drv.run(); // Play effect
    
    LOG_I(TAG, "Effect played (ID): %d", effectId);

    // Start the timer that automatically turn off the chip in 500ms
    if (powerOffTimer != nullptr){
        xTimerStart(powerOffTimer, 0);
    }
}

void HapticManager::powerOffTimerCallback(TimerHandle_t xTimer) {
    // This timer runs in the background after 500ms as defined
    digitalWrite(HAPTIC_EN_PIN, LOW);
    LOG_I(TAG, "Haptic motor powered off to save energy.");
}