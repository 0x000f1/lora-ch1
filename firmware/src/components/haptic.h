/**
 * @file haptic.h
 * @brief Haptic feedback functions with DRV2605L motor driver.
 * @details This component will handle the initialization and control of the motor driver.
 */

#ifndef HAPTIC_H
#define HAPTIC_H

#include <Arduino.h>
#include <Adafruit_DRV2605.h>

class HapticManager {
    public:
        /** 
         * @brief Initialize the Haptic driver.
         * @return 0 on success, error code on failure.
         * @details See haptic.cpp for pin configuration and initialization steps.
         */
        static int setupHaptic();
        /**
         * @brief Play a haptic effect.
         * @param effectNumber The number selects the effect to be played. See DRV2605L documentation for effect numbers.
         * @details This function will play the specified haptic effect on the motor driver.
         */
        static void playEffect(int effectNumber);
};
#endif