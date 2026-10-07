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
    uint32_t senderAddress; // Address of the sender
    uint32_t targetAddress; // Address of the target (0xFFFF for broadcast)
    uint8_t packageType; // Type of the package (data, discovery, etc.)
    uint8_t sequenceNumber; // ID for the package (for tracking and acknowledgment)
    uint8_t currentFragment; // Number of the current fragment
    uint8_t totalFragments; // Total number of fragments in this package
} __attribute__((packed)); // The padding bits are removed

// Structure for acknowledgment payload
struct AckPayload {
    uint8_t sequenceNumber; // Sequence number being acknowledged
    uint8_t currentFragment; // Fragment number being acknowledged
} __attribute__((packed));

// Structure for discovery/heartbeat payload
struct DiscoveryPayload {
    char username[20]; // Username of the sender
    uint8_t colorR; // Red color component
    uint8_t colorG; // Green color component
    uint8_t colorB; // Blue color component
    float latitude; // Geo latitude
    float longitude; // Geo longitude
} __attribute__((packed));

// Structure for neighbor information
struct DiscoveryInfo {
    uint32_t senderAddress; // Address of the neighbor
    char senderUsername[20]; // Username of the sender
    uint8_t colorR; // Red color component
    uint8_t colorG; // Green color component
    uint8_t colorB; // Blue color component
    uint8_t sequenceNumber; // Sequence number of the last received packet
    float latitude; // Geo latitude
    float longitude; // Geo longitude
    unsigned long timestamp; // Last seen timestamp
    unsigned long lastSeenMillis; // Last seen in millis for timeout
    float rssi; // RSSI value of the last received message
    float snr; // SNR value of the last received message
};
#endif