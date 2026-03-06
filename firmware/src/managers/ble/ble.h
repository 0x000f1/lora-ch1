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
         * @details This function initializes the BLE hardware, creates a server, service, and characteristic.
        */
        static int setupBLE();
        /**
         * @brief Pushes a message to all connected BLE clients.
         * @param message The message to be sent.
         * @details This function sets the value of the characteristic and sends a notification to all connected clients.
        */
        static void pushMessage(const char* message);
        /**
         * @brief Starts the pairing mode, set the BLE to advertising mode.
         * @details It starts to advertise the device in a 60 sec window to able to pair.
         */
        static void startPairingMode();
        /**
         * @brief It stops the pairing mode, stop the BLE advertisement.
         */
        static void stopPairingMode();
    private:
        // Timers for the 60s advertisement
        static TimerHandle_t pairingTimer;
        static void pairingTimerCallback(TimerHandle_t xTimer);
};
#endif