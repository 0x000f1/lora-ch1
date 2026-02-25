/**
 * @file lora.h
 * @brief LoRa communication functions.
 * @details This component will handle LoRa communication, initialization and message sending.
 * @todo Implement addressing, message queuing.
 */

#ifndef LORA_H
#define LORA_H

#include <Arduino.h>
#include "protocol/protocol.h"

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
         * @param data The pointer of the data to be sent.
         * @param length The length of the data to be sent.
         * @param targetAddress The address of the target (default is broadcast).
         * @param packageType The type of the package (default is data). (See PackageType enum in protocol.h)
         * @details This function will handle the transmission of messages over LoRa. It will also implement a simple CAD mechanism to avoid collisions.
         * @todo Implement a CAD mechanism and message fragmentation.
         */
        static void sendMessage(uint8_t* data, size_t length, uint32_t targetAddress = BROADCAST_ADDRESS, PackageType packageType = PKG_DATA);
        static void handleFlags();
    private:
        static void setFlag();
        static uint8_t currentSequenceNumber; // Sequence number for messages
};
#endif