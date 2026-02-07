#include <Arduino.h>
#include "config.h"
#include "components/ble.h"

void setup() {
    Serial.begin(115200);
    
    setupBLE(DEVICE_NAME);
}

void loop() {
    pushMessage("Hello from ESP32!");
    delay(5000);
}