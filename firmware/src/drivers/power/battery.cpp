#include "battery.h"
#include "utils/log_helper.h"

#define TAG "POWER"

PowerProfile BatteryManager::currentProfile = PowerProfile::BALANCED; // Default profile

void BatteryManager::setPowerProfile(PowerProfile profile) {
    currentProfile = profile;
    switch (profile) {
        case PowerProfile::BATTERY_SAVER:
            setCpuFrequencyMhz(40);
            LOG_I(TAG, "Power profile set to BATTERY_SAVER (40 MHz)");
            break;
        case PowerProfile::BALANCED:
            setCpuFrequencyMhz(80);
            LOG_I(TAG, "Power profile set to BALANCED (80 MHz)");
            break;
        case PowerProfile::PERFORMANCE:
            setCpuFrequencyMhz(160);
            LOG_I(TAG, "Power profile set to PERFORMANCE (160 MHz)");
            break;
    }
}

const char* BatteryManager::getPowerProfile() {
    switch (currentProfile) {
        case PowerProfile::BATTERY_SAVER: return "BATTERY_SAVER";
        case PowerProfile::BALANCED: return "BALANCED";
        case PowerProfile::PERFORMANCE: return "PERFORMANCE";
        default: return "UNKNOWN";
    }
}