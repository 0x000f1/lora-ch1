#include "button.h"
#include "utils/log_helper.h"
#include "drivers/ui/haptic.h"

#define TAG "BUTTON"
#define BUTTON_PIN 1
#define DEBOUNCE_MS 250 // 250ms debouncing time (to avoid button press errors)

volatile bool ButtonManager::buttonPressedFlag = false;
volatile unsigned long ButtonManager::lastPressTime = 0;

// This function is called via the physical button press, when the current changes on the pin (GPIO1)
void IRAM_ATTR ButtonManager::isr() {
    unsigned long currentTime = millis();
    // Debouncing : Only accept the button press, if 250ms elapsed since last press
    if (currentTime - lastPressTime > DEBOUNCE_MS) {
        buttonPressedFlag = true;
        lastPressTime = currentTime;
    }
}

void ButtonManager::setupButton() {
    LOG_I(TAG, "Initializing Button on GPIO %d...", BUTTON_PIN);
    
    // INPUT_PULLUP: Pull the GPIO leg to HIGH via an internal pullup resistor.
    pinMode(BUTTON_PIN, INPUT_PULLUP);
    
    // Interrupt: FALLING -> The current jumps from HIGHT to LOW.
    attachInterrupt(digitalPinToInterrupt(BUTTON_PIN), isr, FALLING);
}

void ButtonManager::handleButton() {
    if (buttonPressedFlag) {
        buttonPressedFlag = false;
        LOG_I(TAG, "Button pressed.");
        
        HapticManager::playEffect(7); // Soft bump - 100% feedback on button pressed
    }
}