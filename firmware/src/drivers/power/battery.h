/**
 * @file battery.h
 * @brief Battery management definitions.
 * @details This file defines the functions and constants related to battery management, such as reading battery voltage, setting the power profile.
 */

#ifndef BATTERY_H
#define BATTERY_H

#include <Arduino.h>
#include "utils/log_helper.h"

enum class PowerProfile {
    BATTERY_SAVER, // 40 MHz - Ultra low performance
    BALANCED, // 80 MHz - Optimized for BLE
    PERFORMANCE // 160 MHz - Maximum performance
};

class BatteryManager {
public:
    /** 
     * @brief Changes the power profile of the device.
     * @param profile The desired power profile to set. (BATTERY_SAVER, BALANCED, PERFORMANCE)
    */
    static void setPowerProfile(PowerProfile profile);
    /**
     * @brief Get the current battery profile in string
     * @return The current battery profile as a string.
     */
    static const char* getPowerProfile();
private:
    static PowerProfile currentProfile;
};

#endif