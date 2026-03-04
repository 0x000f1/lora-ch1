/**
 * @file button.h
 * @brief The physical button initialization and handle button press with interrupts.
 */

#ifndef BUTTON_H
#define BUTTON_H

#include <Arduino.h>

class ButtonManager {
    public:
        /** 
         * @brief Initialize the Button.
         * @details See button.cpp for pin configuration and initialization steps.
         */
        static void setupButton();
        /**
         * @brief Handle the button press event.
         * @details This function will handle the event with interrupt.
         */
        static void handleButton();
    private:
        static void IRAM_ATTR isr(); // The Interrupt Service Routine (kept in RAM)
        static volatile bool buttonPressedFlag;
        static volatile unsigned long lastPressTime;
};
#endif