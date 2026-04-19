#include "lora.h"
#include "utils/log_helper.h"
#include "managers/ble/ble.h"
#include "managers/system/system_manager.h"
#include "drivers/ui/haptic.h"
#include <SPI.h>
#include <RadioLib.h>

#define TAG "LORA"
#define BAND 433.0
#define BANDWIDTH 125.0
#define SPREADING_FACTOR 8
#define CODING_RATE 5
#define SYNC_WORD 0x12
#define POWER 10
#define PREAMBLE_LENGTH 12 // OLD(1 symbol: 2.048ms, 150 symbol ~ 300ms) NEW DEFAULT 12
#define GAIN 0

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

TimerHandle_t LoRaManager::ackTimer = nullptr;
volatile bool LoRaManager::ackTimeoutPending = false;
uint8_t LoRaManager::retryCount = 0;
const uint8_t LoRaManager::MAX_RETRIES = 3; // Max 3 retries before drop the package
volatile bool LoRaManager::waitingForAck = false;

uint8_t LoRaManager::lastPayload[PAYLOAD_SIZE];
size_t LoRaManager::lastPayloadLength = 0;
uint32_t LoRaManager::lastTargetAddress = 0;
uint8_t LoRaManager::lastCurrentFragment = 0;
uint8_t LoRaManager::lastTotalFragment = 0;

volatile bool LoRaManager::txPending = false;
uint8_t LoRaManager::txPendingPayload[PAYLOAD_SIZE];
size_t LoRaManager::txPendingLength = 0;
uint32_t LoRaManager::txPendingTarget = 0;
uint8_t LoRaManager::txPendingCurrentFrag = 0;
uint8_t LoRaManager::txPendingTotalFrag = 0;

// CAD variables
// timerHandle_t LoRaManager::cadRxTimer = nullptr;
// volatile bool LoRaManager::cadCheckPending = false;
// TimerHandle_t LoRaManager::rxTimeoutTimer = nullptr;
// volatile bool LoRaManager::rxTimeoutPending = false;

// void LoRaManager::cadRxTimerCallback(TimerHandle_t xTimer) {
    // cadCheckPending = true; 
// }
// void LoRaManager::rxTimeoutTimerCallback(TimerHandle_t xTimer) {
    // rxTimeoutPending = true;
// }

SPIClass loraSPI(FSPI); // FSPI = SPI2 | Use the FSPI for custom pin configuration
SX1278 loraModule = new Module(LORA_NSS, LORA_DIO0, LORA_RST, RADIOLIB_NC, loraSPI);

volatile bool actionFlag = false; // Interrupt flag to show receive/transmit events.
bool isTransmitting = false;      // Current state: true = waiting for transmission to finish, false = waiting for package.
// bool isScanning = false;          // true = CAD scanning in the background

// Interrupt callback stored in RAM to ensure fast access.
void ICACHE_RAM_ATTR LoRaManager::setFlag() {
    actionFlag = true;
}

int LoRaManager::setupLoRa() {
    loraSPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_NSS);
    statsStartTime = millis(); // Start the timer for duty cycle statistics.

    // Timers
    ackTimer = xTimerCreate("ackTimer", pdMS_TO_TICKS(2000), pdFALSE, nullptr, ackTimerCallback);
    // CAD Timer
    // cadRxTimer = xTimerCreate("cadRxTimer", pdMS_TO_TICKS(100), pdTRUE, nullptr, cadRxTimerCallback);
    // rxTimeoutTimer = xTimerCreate("rxTimeoutTimer", pdMS_TO_TICKS(1500), pdFALSE, nullptr, rxTimeoutTimerCallback); // If the CAD alert was false

    LOG_I(TAG, "Initializing SX1278...");
    int state = loraModule.begin(BAND, BANDWIDTH, SPREADING_FACTOR, CODING_RATE, SYNC_WORD, POWER, PREAMBLE_LENGTH, GAIN);
    if (state != RADIOLIB_ERR_NONE) {
        LOG_E(TAG, "Setup failed, code: %d", state);
        return state;
    }

    // Register callbacks (Receive and Transmit completion).
    loraModule.setPacketReceivedAction(setFlag);
    loraModule.setPacketSentAction(setFlag);
    loraModule.setChannelScanAction(setFlag);

    startReceive(); // Start listening for incoming messages.
    return 0;
}

void LoRaManager::startReceive() {
    // loraModule.standby();
    isTransmitting = false;
    // isScanning = false;

    int state = loraModule.startReceive();
    if (state != RADIOLIB_ERR_NONE) {
        LOG_E(TAG, "Failed to start receive: %d", state);
    }

    // if (cadRxTimer != nullptr) xTimerStart(cadRxTimer, 0); // Start the CAD cycle
}

void LoRaManager::queueMessage(uint8_t* data, size_t length, uint32_t targetAddress, uint8_t currentFragment, uint8_t totalFragment) {
    if (length > PAYLOAD_SIZE) return;
    
    memcpy(txPendingPayload, data, length);
    txPendingLength = length;
    txPendingTarget = targetAddress;
    txPendingCurrentFrag = currentFragment;
    txPendingTotalFrag = totalFragment;
    
    txPending = true;
}

void LoRaManager::sendMessage(uint8_t* data, size_t length, uint32_t targetAddress, uint8_t currentFragment, uint8_t totalFragment, PackageType packageType, bool isRetry) {
    LOG_I(TAG, "Preparing to send data of length %d", length);
    // if (cadRxTimer != nullptr) xTimerStop(cadRxTimer, 0); // Stop CAD while transmitting
    
    if (length > (PAYLOAD_SIZE - sizeof(PackageHeader))) {
        LOG_E(TAG, "Data length exceeds payload size...");
        return;
    }

    if (packageType == PKG_DATA && targetAddress != BROADCAST_ADDRESS) {
        if (!isRetry) {
            // If the message is new (not resending), save the parameters
            memcpy(lastPayload, data, length);
            lastPayloadLength = length;
            lastTargetAddress = targetAddress;
            lastCurrentFragment = currentFragment;
            lastTotalFragment = totalFragment;
            retryCount = 0;
        }
        waitingForAck = true;
        if (ackTimer != nullptr) xTimerStart(ackTimer, 0);
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

    // if (cadRxTimer != nullptr) xTimerStop(cadRxTimer, 0); 
    
    loraModule.standby(); 
    // isScanning = false;
    actionFlag = false;
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
    if (txPending) {
        txPending = false;
        sendMessage(txPendingPayload, txPendingLength, txPendingTarget, txPendingCurrentFrag, txPendingTotalFrag, PKG_DATA);
    }

    if (heartbeatPending) {
        heartbeatPending = false;
        sendMessage(nullptr, 0, BROADCAST_ADDRESS, 1, 1, PKG_HEARTBEAT); // Sends a heartbeat message to broadcast
        
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
    }

    // If the 2 seconds elapsed, and not received ACK type package
    if (ackTimeoutPending) {
        ackTimeoutPending = false;
        if (waitingForAck) {
            if (retryCount < MAX_RETRIES) {
                retryCount++;
                LOG_W(TAG, "ACK timeout! Retrying send message to 0x%08X (Attempt %d/%d)", lastTargetAddress, retryCount, MAX_RETRIES);
                sendMessage(lastPayload, lastPayloadLength, lastTargetAddress, lastCurrentFragment, lastTotalFragment, PKG_DATA, true);
            } else {
                LOG_E(TAG, "Max retries reached. Delivery failed to 0x%08X", lastTargetAddress);
                waitingForAck = false;
                HapticManager::playEffect(16); // Long haptic feedback to notify about the error.
                
                // Push BLE message that shows the error.
                char errorMsg[50];
                snprintf(errorMsg, sizeof(errorMsg), "ERR_TIMEOUT;%08X", lastTargetAddress);
                BLEManager::pushMessage(errorMsg);
            }
        }
    }

    // CAD and timeout handling
    // if (rxTimeoutPending) {
        // rxTimeoutPending = false;
        // LOG_W(TAG, "RX Timeout: False CAD alarm. Going back to sleep.");
        // startReceive(); // Back to 'sleep'
    // }

    // Async CAD start
    // if (cadCheckPending) {
        // cadCheckPending = false;
        
        // loraModule.standby();
        // isScanning = true; // Indicate that scanning started
        // int state = loraModule.startChannelScan(); // NON blocking, means continue!
        
        // if (state != RADIOLIB_ERR_NONE) {
            // LOG_E(TAG, "CAD Start failed: %d", state);
            // isScanning = false;
            // loraModule.standby();
        // }
    // }

    if (!actionFlag) return;

    actionFlag = false; // Reset the flag to avoid missing future events.

    // if (isScanning) {
        // A) CAD scan finished in the background
        // isScanning = false;
        // int cadResult = loraModule.getChannelScanResult(); // Get result
        
        // if (cadResult == RADIOLIB_LORA_DETECTED) {
            // LOG_I(TAG, "CAD: Activity detected! Waking up receiver...");
            // xTimerStop(cadRxTimer, 0);       
            // loraModule.startReceive();       
            // xTimerStart(rxTimeoutTimer, 0);  
        // } else {
            // loraModule.standby(); // Air is empty, go back to sleep
        // }
    // } else if (isTransmitting) {
    if (isTransmitting) {
        // B) TX finished
        // This means the transmission has just completed.
        loraModule.finishTransmit();
        LOG_I(TAG, "Transmission finished!");
        startReceive(); // Jump back to receive mode.
    } else {
        // C) RX finished
        // This means a new message just arrived.
        // if (rxTimeoutTimer != nullptr) xTimerStop(rxTimeoutTimer, 0); // Receive success, delete Watchdog timer

        size_t len = loraModule.getPacketLength();
        uint8_t rxBuffer[PAYLOAD_SIZE];

        int state = loraModule.readData(rxBuffer, len);

        if (state == RADIOLIB_ERR_NONE && len >= sizeof(PackageHeader)) {
            PackageHeader header;
            memcpy(&header, rxBuffer, sizeof(PackageHeader));

            uint8_t* payload = rxBuffer + sizeof(PackageHeader);
            size_t payloadLength = len - sizeof(PackageHeader);

            LOG_I(TAG, "RX from 0x%08X, RSSI: %f, Type: %d", header.senderAddress, loraModule.getRSSI(), header.packageType);
            
            // Update neighbors list with the sender's address and RSSI
            updateNeighbor(header.senderAddress, loraModule.getRSSI());

            // Convert to char array if it's a DATA package and forward to BLE Manager.
            // Check if the package is sent for BROADCAST or to this device's address.
            bool packageIsForMe = (header.targetAddress == BROADCAST_ADDRESS ||
                                    header.targetAddress == (uint32_t)SystemManager::getLoRaID());

            if (!packageIsForMe) LOG_I(TAG, "Ignored package: Different target address! (0x%08X)", header.targetAddress);
            // The received package is for BROADCAST or for this device
            else {
                // If the message is an ACK package.
                if (header.packageType == PKG_ACK && waitingForAck && header.senderAddress == lastTargetAddress) {
                    LOG_I(TAG, "ACK received from 0x%08X! Message delivered successfully.", header.senderAddress);
                    waitingForAck = false;
                    if (ackTimer != nullptr) xTimerStop(ackTimer, 0); // Stop the ACK timer on success.
                    
                    // Push BLE message that shows the success.
                    char successMsg[50];
                    snprintf(successMsg, sizeof(successMsg), "ACK_OK;%08X", header.senderAddress);
                    BLEManager::pushMessage(successMsg);
                }

                if (header.packageType == PKG_DATA && header.targetAddress == (uint32_t)SystemManager::getLoRaID()){
                    // If the message has been received is for this device (P2P communication), send back an ACK type message.
                    LOG_I(TAG, "P2P type message received, sending back ACK to 0x%08X", header.senderAddress);
                    sendMessage(nullptr, 0, header.senderAddress, 1, 1, PKG_ACK);
                }

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
                    HapticManager::playEffect(52); // Pulsing strong 1 - 100% feedback on message received.
                    BLEManager::pushMessage(formattedString); // Forward the message to the BLE Manager to notify connected clients.
                }
            }
        } else if (state == RADIOLIB_ERR_CRC_MISMATCH) {
            LOG_W(TAG, "CRC Error!");
        } else {
            LOG_E(TAG, "Receive failed, code: %d", state);
        }

        if (!isTransmitting) {
            startReceive();
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

void LoRaManager::ackTimerCallback(TimerHandle_t xTimer) {
    ackTimeoutPending = true; // The timer expired
}