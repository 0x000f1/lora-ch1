/**
 * @file lora.h
 * @brief LoRa communication functions.
 * @details This component will handle LoRa communication, initialization and message sending.
 * @todo Implement addressing, message queuing.
 */

#ifndef LORA_H
#define LORA_H

#include <Arduino.h>

class LoRaManager {
    public:
        /** 
         * @brief Initialize the LoRa module.
         * @return 0 on success, error code on failure.
         * @details See lora.cpp for pin configuration and initialization steps.
         */
        static int setupLoRa();
        /**
         * @brief Start receiving messages over LoRa.
         * @details This function will put the LoRa module in receive mode, allowing it to listen for incoming messages.
         */
        static void startReceive();
        /**
         * @brief Send a message over LoRa.
         * @param message The message to be sent.
         * @details This function will handle the transmission of messages over LoRa. It will also implement a simple CAD mechanism to avoid collisions.
         * @todo Implement a CAD mechanism and message fragmentation.
         */
        static void sendMessage(String message);
        static void handleFlags();
    private:
        static void setFlag();
};
#endif