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
    BATTERY_SAVER, // 80 MHz - Ultra low performance
    BALANCED, // 80 MHz - Optimized for BLE
    PERFORMANCE // 160 MHz - Maximum performance
};

class BatteryManager {
public:
    /**
     * @brief Initializes the ADC and charging indicator pin.
     */
    static void setupBattery();

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
    /**
     * @brief Returns the battery current level (0-100)
     */
    static uint8_t getBatteryPercentage();
    /**
     * @brief Checks the charging status
     * @return true if charging, false is discharging
     */
    static bool isCharging();
private:
    static PowerProfile currentProfile;
};

#endif