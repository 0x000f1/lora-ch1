/**
 * @file lora.h
 * @brief LoRa communication functions.
 * @details This component will handle LoRa communication, initialization and message sending.
 * @todo Implement message queuing, finish heartbeat
 */

#ifndef LORA_H
#define LORA_H

#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/timers.h>
#include "protocol/protocol.h"

#define PAYLOAD_SIZE 250
#define MAX_NEIGHBORS 20

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
         * @param currentFragment The current fragment number (Starts from 1).
         * @param totalFragment The number of all the fragments in the package (Default 0).
         * @param packageType The type of the package (default is data). (See PackageType enum in protocol.h)
         * @param isRetry The message is failed to send on first try, so retry it. (default is False).
         * @details This function will handle the transmission of messages over LoRa. It will also implement a simple CAD mechanism to avoid collisions.
         * @todo Implement a CAD mechanism.
         */
        static void sendMessage(uint8_t* data,
                                size_t length,
                                uint32_t targetAddress = BROADCAST_ADDRESS,
                                uint8_t currentFragment = 1,
                                uint8_t totalFragment = 1,
                                PackageType packageType = PKG_DATA,
                                bool isRetry = false);
        /**
         * @brief Queue a message to be sent. (Thread safe from BLE task calls)
         */
        static void queueMessage(uint8_t* data,
                                size_t length,
                                uint32_t targetAddress,
                                uint8_t currentFragment,
                                uint8_t totalFragment);
        static void handleFlags();
        /**
         * @brief Start sending heartbeat messages at given intervals.
         * @param intervalSeconds The interval in seconds between heartbeat messages.
         */
        static void startHeartbeat(uint16_t intervalSeconds);
        static void stopHeartbeat();
        /**
         * @brief Return the list of known neighbors and their RSSI values.
          * @details This function will return the list of known neighbors and their RSSI values.
         */
        static DiscoveryInfo* getNeighbors(uint8_t &count) {
            count = neighborCount;
            return neighbors;
        };
    private:
        // Basic LoRa variables
        static void setFlag();
        static uint8_t currentSequenceNumber; // Sequence number for messages

        // Heartbeat
        static TimerHandle_t heartbeatTimer; // FreeRTOS timer for heartbeat messages
        static volatile bool heartbeatPending; // Flag to show that a heartbeat is pending
        static void heartbeatTimerCallback(TimerHandle_t xTimer);
        
        // Air Time and Duty Cycle
        static uint32_t totalAirTimeMs;
        static unsigned long statsStartTime;
        static void updateDutyCycle(uint32_t currentAirTimeMs);

        // Neighbors
        static DiscoveryInfo neighbors[MAX_NEIGHBORS];
        static uint8_t neighborCount;
        static void updateNeighbor(uint32_t senderAddress, float rssi);

        // ACK and Resend variables
        static TimerHandle_t ackTimer;
        static volatile bool ackTimeoutPending;
        static void ackTimerCallback(TimerHandle_t xTimer);

        static uint8_t retryCount;
        static const uint8_t MAX_RETRIES;
        static volatile bool waitingForAck;

        // Save the last message to the internal memory (If it needed for resend)
        static uint8_t lastPayload[PAYLOAD_SIZE];
        static size_t lastPayloadLength;
        static uint32_t lastTargetAddress;
        static uint8_t lastCurrentFragment;
        static uint8_t lastTotalFragment;

        // Message queueing thread-safe variables
        static volatile bool txPending;
        static uint8_t txPendingPayload[PAYLOAD_SIZE];
        static size_t txPendingLength;
        static uint32_t txPendingTarget;
        static uint8_t txPendingCurrentFrag;
        static uint8_t txPendingTotalFrag;

        // Wake on radio (CAD) variables
        // static TimerHandle_t cadRxTimer;
        // static volatile bool cadCheckPending;
        // static void cadRxTimerCallback(TimerHandle_t xTimer);

        // static TimerHandle_t rxTimeoutTimer;
        // static volatile bool rxTimeoutPending;
        // static void rxTimeoutTimerCallback(TimerHandle_t xTimer);
};
#endif