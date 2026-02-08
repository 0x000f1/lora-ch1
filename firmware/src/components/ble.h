/**
 * @file ble.h
 * @brief Bluetooth Low Energy functions.
 */

#ifndef BLE_H
#define BLE_H
#include <Arduino.h>

class BLEManager {
public:
    /**
     * @brief Starts the BLE hardware and advertising the device.
     * @return int Status code:
     *  0: Success
     *  1: Server start error
     *  2: Service start error
     *  3: Characteristic creation error
     *  4: Advertising start error
     * @details This function initializes the BLE hardware, creates a server, service, and characteristic.
     * @todo Security, and support for multiple characteristics and services.
    */
    static int setupBLE();

    /**
     * @brief Pushes a message to all connected BLE clients.
     * @param message The message to be sent.
     * @details This function sets the value of the characteristic and sends a notification to all connected clients.
     * @todo Implement message queuing and support for larger messages that may require fragmentation.
    */
    static void pushMessage(const char* message);
};
#endif