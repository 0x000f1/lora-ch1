/** 
 * @file protocol.h
 * @brief Protocol definitions for LoRa communication.
 * @details This file defines the structure of the messages that will be sent and received over LoRa.
*/

#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <Arduino.h>

const uint32_t BROADCAST_ADDRESS = 0xFFFFFFFF; // Address used for broadcasting

// Define the type of messages (to identify the received package type)
enum PackageType : uint8_t {
    PKG_UNKNOWN = 0x00, // Unknown package type
    PKG_DATA = 0x01, // Regular data message
    PKG_HEARTBEAT = 0x02, // Send out a discovery (who is here?) message
    PKG_ACK = 0x04, // Acknowledgment for received messages
};

// Header of the package (every package will have this header)
struct PackageHeader {
    uint32_t senderAddress; // Address of the sender @todo Implement addressing scheme
    uint32_t targetAddress; // Address of the target (0xFFFF for broadcast)
    uint8_t packageType; // Type of the package (data, discovery, etc.)
    uint8_t sequenceNumber; // ID for the package (for tracking and acknowledgment)
    uint8_t currentFragment; // Number of the current fragment
    uint8_t totalFragments; // Total number of fragments in this package
} __attribute__((packed)); // The padding bits are removed

#endif