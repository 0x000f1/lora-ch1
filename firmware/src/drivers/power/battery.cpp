#include "battery.h"
#include "utils/log_helper.h"

#define TAG "POWER"

#define PIN_BATTERY_ADC 0
#define PIN_BATTERY_CHARGE 20

PowerProfile BatteryManager::currentProfile = PowerProfile::BALANCED; // Default profile

void BatteryManager::setupBattery() {
    LOG_I(TAG, "Initializing Battery Manager...");
    analogSetPinAttenuation(PIN_BATTERY_ADC, ADC_11db);
    pinMode(PIN_BATTERY_CHARGE, INPUT);
}

void BatteryManager::setPowerProfile(PowerProfile profile) {
    currentProfile = profile;
    uint32_t cpuFreq = 80; // Default to BALANCED

    switch (profile) {
        case PowerProfile::BATTERY_SAVER:   cpuFreq = 80; break;
        case PowerProfile::BALANCED:        cpuFreq = 80; break;
        case PowerProfile::PERFORMANCE:     cpuFreq = 160; break;
    }
    setCpuFrequencyMhz(cpuFreq);
    LOG_I(TAG, "Power profile: %s | CPU: %d MHz", getPowerProfile(), cpuFreq);
}

const char* BatteryManager::getPowerProfile() {
    switch (currentProfile) {
        case PowerProfile::BATTERY_SAVER: return "BATTERY_SAVER";
        case PowerProfile::BALANCED: return "BALANCED";
        case PowerProfile::PERFORMANCE: return "PERFORMANCE";
        default: return "UNKNOWN";
    }
}

bool BatteryManager::isCharging() {
    // The BQ24075 open drain ouput is LOW when CHARING
    return digitalRead(PIN_BATTERY_CHARGE) == LOW;
}

uint8_t BatteryManager::getBatteryPercentage() {
    // analogReadMilliVolts is more advanced than analogRead
    uint32_t adcMilliVolts = analogReadMilliVolts(PIN_BATTERY_ADC);

    // The measured voltage is the half of the battery's.
    float voltageBattery = (adcMilliVolts * 2.0f) / 1000.0f;

    // Calculate the percentage (3.2 - 4.2 V range)
    float percentageBattery = ((voltageBattery - 3.2f) / (4.2f - 3.2f)) * 100.0f;

    // Handling limits and measurement errors
    if (percentageBattery > 100.0f) percentageBattery = 100.0f;
    if (percentageBattery < 0.0f) percentageBattery = 0.0f;

    return (uint8_t)percentageBattery;
}