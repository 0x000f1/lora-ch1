#include "battery.h"
#include "utils/log_helper.h"

#define TAG "POWER"

PowerProfile BatteryManager::currentProfile = PowerProfile::BALANCED; // Default profile

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