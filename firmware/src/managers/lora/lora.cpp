#include "lora.h"
#include "utils/log_helper.h"
#include "managers/ble/ble.h"
#include "managers/system/system_manager.h"
#include <SPI.h>
#include <RadioLib.h>

#define TAG "LORA"
#define PAYLOAD_SIZE 250 // SX1278 can handle 255 bytes, but keep a little below the limit
#define BAND 433.0

#define LORA_SCK  4
#define LORA_MISO 5
#define LORA_MOSI 6
#define LORA_NSS  7
#define LORA_RST  3
#define LORA_DIO0 10

// Static variables (Heartbeat, sequence number, duty cycle stats, neighbors)
TimerHandle_t LoRaManager::heartbeatTimer = nullptr;
volatile bool LoRaManager::heartbeatPending = false;
uint8_t LoRaManager::currentSequenceNumber = 0; // Initialize sequence number
uint32_t LoRaManager::totalAirTimeMs = 0;
unsigned long LoRaManager::statsStartTime = 0;
DiscoveryInfo LoRaManager::neighbors[MAX_NEIGHBORS];
uint8_t LoRaManager::neighborCount = 0;


SPIClass loraSPI(FSPI); // FSPI = SPI2 | Use the FSPI for custom pin configuration
SX1278 loraModule = new Module(LORA_NSS, LORA_DIO0, LORA_RST, RADIOLIB_NC, loraSPI);

volatile bool actionFlag = false; // Interrupt flag to show receive/transmit events.
bool isTransmitting = false;      // Current state: true = waiting for transmission to finish, false = waiting for package.

// Interrupt callback stored in RAM to ensure fast access.
void ICACHE_RAM_ATTR LoRaManager::setFlag() {
    actionFlag = true;
}

int LoRaManager::setupLoRa() {
    loraSPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_NSS);
    statsStartTime = millis(); // Start the timer for duty cycle statistics.
    
    LOG_I(TAG, "Initializing SX1278...");
    int state = loraModule.begin(BAND);
    if (state != RADIOLIB_ERR_NONE) {
        LOG_E(TAG, "Setup failed, code: %d", state);
        return state;
    }

    // Register callbacks (Receive and Transmit completion).
    loraModule.setPacketReceivedAction(setFlag);
    loraModule.setPacketSentAction(setFlag);

    startReceive(); // Start listening for incoming messages.
    return 0;
}

void LoRaManager::startReceive() {
    loraModule.standby();
    int state = loraModule.startReceive();
    if (state == RADIOLIB_ERR_NONE) {
        isTransmitting = false;
        LOG_I(TAG, "Listening for incoming messages...");
    } else {
        LOG_E(TAG, "Starting receive failed: %d", state);
    }
}

void LoRaManager::sendMessage(uint8_t* data, size_t length, uint32_t targetAddress, uint8_t currentFragment, uint8_t totalFragment, PackageType packageType) {
    LOG_I(TAG, "Preparing to send data of length %d", length);
    
    // There will be used a CAD (Channel Activity Detection) before transmission to avoid collisions. If the channel is busy, it will wait and retry.
    
    if (length > (PAYLOAD_SIZE - sizeof(PackageHeader))) {
        LOG_E(TAG, "Data length exceeds payload size...");
        return;
    }

    PackageHeader header;
    header.senderAddress = SystemManager::getLoRaID();
    header.targetAddress = targetAddress;
    header.packageType = packageType;
    header.sequenceNumber = currentSequenceNumber++;
    header.currentFragment = currentFragment;
    header.totalFragments = totalFragment;

    // Combine header into one message buffer
    uint8_t txBuffer[PAYLOAD_SIZE];
    memcpy(txBuffer, &header, sizeof(PackageHeader));
    memcpy(txBuffer + sizeof(PackageHeader), data, length);

    // Air Time calculation for statistics and duty cycle measurement
    float airTime = loraModule.getTimeOnAir(sizeof(PackageHeader) + length) / 1000.0f; // Convert to milliseconds

    LOG_I(TAG, "TX to 0x%08X | Type: %d | Air Time: %.2f ms | Package %d of %d", targetAddress, packageType, airTime, currentFragment, totalFragment);

    isTransmitting = true;
    int state = loraModule.startTransmit(txBuffer, sizeof(PackageHeader) + length);
    
    if (state != RADIOLIB_ERR_NONE) {
        LOG_E(TAG, "Transmit start failed: %d", state);
        startReceive(); // Return to receive mode if transmission fails.
    }else{
        updateDutyCycle((uint32_t)airTime); // Update duty cycle stats with the current air time.
    }
}

void LoRaManager::updateDutyCycle(uint32_t currentAirTimeMs) {
    totalAirTimeMs += currentAirTimeMs;
    unsigned long elapsedTime = millis() - statsStartTime;

    if (elapsedTime > 0) {
        float dutyCycle = (totalAirTimeMs / (float)elapsedTime) * 100.0f;
        LOG_I(TAG, "Duty Cycle: %.2f%% | Total Air Time: %lu ms | Elapsed Time: %lu ms", dutyCycle, totalAirTimeMs, elapsedTime);
    }
}

void LoRaManager::handleFlags() {
    if (heartbeatPending) {
        heartbeatPending = false;
        sendMessage(nullptr, 0, BROADCAST_ADDRESS, 1, 1, PKG_HEARTBEAT); // Sends a heartbeat message to broadcast
    }

    // Delete the inactive neighbors (That device has been inactive for 120 sec).
    unsigned long currentMillis = millis();
    uint32_t timeoutMs = 120000; // 120 sec -> 120 000 ms

    for (uint8_t i = 0; i < neighborCount;) {
        if (currentMillis - neighbors[i].timestamp > timeoutMs){
            LOG_I(TAG, "Neighbor timeout, removed: 0x%08X", neighbors[i].senderAddress);
            for (uint8_t j = i; j < neighborCount - 1; j++){
                neighbors[j] = neighbors[j + 1];
            }
            neighborCount--;
        } else {
            i++;
        }
    }

    if (!actionFlag) return;

    actionFlag = false; // Reset the flag to avoid missing future events.

    if (isTransmitting) {
        // This means the transmission has just completed.
        loraModule.finishTransmit();
        LOG_I(TAG, "Transmission finished!");
        startReceive(); // Jump back to receive mode.
    } else {
        // This means a new message just arrived.
        size_t len = loraModule.getPacketLength();
        uint8_t rxBuffer[PAYLOAD_SIZE];

        int state = loraModule.readData(rxBuffer, len);

        if (state == RADIOLIB_ERR_NONE && len >= sizeof(PackageHeader)) {
            PackageHeader header;
            memcpy(&header, rxBuffer, sizeof(PackageHeader));

            uint8_t* payload = rxBuffer + sizeof(PackageHeader);
            size_t payloadLength = len - sizeof(PackageHeader);

            LOG_I(TAG, "RX from 0x%08X, RSSI: %f, Type: %d", header.senderAddress, loraModule.getRSSI(), header.packageType);
            
            // Convert to char array if it's a DATA package and forward to BLE Manager.
            if (header.packageType == PKG_DATA && payloadLength > 0) {
                char formattedString[PAYLOAD_SIZE + 50]; // Extra space for formatting
                char payloadString[PAYLOAD_SIZE];
                size_t copyLength = (payloadLength < PAYLOAD_SIZE) ? payloadLength : PAYLOAD_SIZE - 1; // Ensure null-termination
                
                memcpy(payloadString, payload, copyLength);
                payloadString[copyLength] = '\0'; // Null-terminate the string

                // Format generation: SENDER_ADDRESS;CURRENT_FRAGMENT;TOTAL_FRAGMENT;PAYLOAD
                snprintf(formattedString, sizeof(formattedString), "%08X;%08X;%d;%d;%s",
                                                                    header.senderAddress,
                                                                    header.targetAddress,
                                                                    header.currentFragment,
                                                                    header.totalFragments,
                                                                    payloadString
                                                                );
                LOG_I(TAG, "Received DATA package: %s", formattedString);

                BLEManager::pushMessage(formattedString); // Forward the message to the BLE Manager to notify connected clients.
            }
            // Update neighbors list with the sender's address and RSSI
            updateNeighbor(header.senderAddress, loraModule.getRSSI());
        } else if (state == RADIOLIB_ERR_CRC_MISMATCH) {
            LOG_W(TAG, "CRC Error!");
        } else {
            LOG_E(TAG, "Receive failed, code: %d", state);
        }
    }
}

void LoRaManager::updateNeighbor(uint32_t senderAddress, float rssi) {
    // Check if the sender is already in the neighbors list
    for (uint8_t i = 0; i < neighborCount; i++) {
        if (neighbors[i].senderAddress == senderAddress) {
            neighbors[i].timestamp = millis(); // Update timestamp (last seen)
            neighbors[i].rssi = rssi; // Update RSSI value (signal strength)
            return;
        }
    }

    // If not found, add the neighbor to the list, if there is space left
    if (neighborCount < MAX_NEIGHBORS) {
        neighbors[neighborCount].senderAddress = senderAddress;
        neighbors[neighborCount].rssi = rssi;
        neighbors[neighborCount].timestamp = millis();
        neighborCount++;
        LOG_I(TAG, "New neighbor added: 0x%08X with RSSI: %f", senderAddress, rssi);
    } else {
        LOG_W(TAG, "Neighbors list full. Cannot add new neighbor: 0x%08X", senderAddress);
    }
}

void LoRaManager::startHeartbeat(uint16_t intervalSeconds) {
    if (heartbeatTimer != nullptr) {
        xTimerStop(heartbeatTimer, 0);
        xTimerDelete(heartbeatTimer, 0);
    }
    heartbeatTimer = xTimerCreate("HeartbeatTimer", pdMS_TO_TICKS(intervalSeconds * 1000), pdTRUE, nullptr, heartbeatTimerCallback);
    xTimerStart(heartbeatTimer, 0);
    LOG_I(TAG, "Heartbeat started with interval: %d seconds", intervalSeconds);
}

void LoRaManager::stopHeartbeat() {
    if (heartbeatTimer != nullptr) {
        xTimerStop(heartbeatTimer, 0);
        xTimerDelete(heartbeatTimer, 0);
        heartbeatTimer = nullptr;
        LOG_I(TAG, "Heartbeat stopped.");
    }
}

void LoRaManager::heartbeatTimerCallback(TimerHandle_t xTimer) {
    heartbeatPending = true; // Set the flag to send a heartbeat (time expired)
}