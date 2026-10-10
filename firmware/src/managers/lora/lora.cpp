#include "lora.h"
#include "utils/log_helper.h"
#include "managers/ble/ble.h"
#include "managers/system/system_manager.h"
#include "drivers/ui/haptic.h"
#include <SPI.h>
#include <RadioLib.h>
#include <time.h>

#define TAG "LORA"
#define BAND 433.175
#define BANDWIDTH 125.0
#define SPREADING_FACTOR 8
#define CODING_RATE 5
#define SYNC_WORD 0x12
#define POWER 10
#define PREAMBLE_LENGTH 12 // 1 symbol: 2.048ms, 12 symbol ~ 25ms)
#define GAIN 0

#define LORA_SCK  4
#define LORA_MISO 5
#define LORA_MOSI 6
#define LORA_NSS  7
#define LORA_RST  2
#define LORA_DIO0 10
#define LORA_DIO1 3

// Static variables (Heartbeat, sequence number, duty cycle stats, neighbors)
TaskHandle_t LoRaManager::mainTaskHandle = NULL;
TimerHandle_t LoRaManager::heartbeatTimer = nullptr;
volatile bool LoRaManager::heartbeatPending = false;
uint8_t LoRaManager::currentSequenceNumber = 0; // Initialize sequence number
uint32_t LoRaManager::totalAirTimeMs = 0;
unsigned long LoRaManager::statsStartTime = 0;
unsigned long LoRaManager::nextTxAllowedMillis = 0;
DiscoveryInfo LoRaManager::neighbors[MAX_NEIGHBORS];
uint8_t LoRaManager::neighborCount = 0;

TimerHandle_t LoRaManager::ackTimer = nullptr;
volatile bool LoRaManager::ackTimeoutPending = false;
uint8_t LoRaManager::retryCount = 0;
const uint8_t LoRaManager::MAX_RETRIES = 3; // Max 3 retries before drop the package
volatile bool LoRaManager::waitingForAck = false;

uint8_t LoRaManager::lastPayload[
    PAYLOAD_SIZE - sizeof(PackageHeader)
];

size_t LoRaManager::lastPayloadLength = 0;
uint32_t LoRaManager::lastTargetAddress = 0;
uint8_t LoRaManager::lastCurrentFragment = 0;
uint8_t LoRaManager::lastTotalFragment = 0;
uint8_t LoRaManager::lastSequenceNumber = 0;

QueueHandle_t LoRaManager::txQueue = nullptr;

uint32_t LoRaManager::heartbeatIntervalSeconds = 300;

LoRaManager::ReceivedPacket
    LoRaManager::receivedCache[MAX_RECEIVED_CACHE];

uint8_t LoRaManager::receivedCacheCount = 0;

// CAD variables
// TimerHandle_t LoRaManager::cadRxTimer = nullptr;
// volatile bool LoRaManager::cadCheckPending = false;
// TimerHandle_t LoRaManager::rxTimeoutTimer = nullptr;
// volatile bool LoRaManager::rxTimeoutPending = false;

// void LoRaManager::cadRxTimerCallback(TimerHandle_t xTimer) {
//     cadCheckPending = true; 
// }
// void LoRaManager::rxTimeoutTimerCallback(TimerHandle_t xTimer) {
//     rxTimeoutPending = true;
// }

SPIClass loraSPI(FSPI); // FSPI = SPI2 | Use the FSPI for custom pin configuration
SX1278 loraModule = new Module(LORA_NSS, LORA_DIO0, LORA_RST, LORA_DIO1, loraSPI);

volatile bool actionFlag = false; // Interrupt flag to show receive/transmit events.
bool isTransmitting = false;      // Current state: true = waiting for transmission to finish, false = waiting for package.
// bool isScanning = false;          // true = CAD scanning in the background

// Interrupt callback stored in RAM to ensure fast access.
void IRAM_ATTR LoRaManager::setFlag() {
    actionFlag = true;

    // FreeRTOS task wake up from interrupt (instantly wake up on received)
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    if (mainTaskHandle != NULL) {
        vTaskNotifyGiveFromISR(mainTaskHandle, &xHigherPriorityTaskWoken);
        if (xHigherPriorityTaskWoken) {
            portYIELD_FROM_ISR(); // Context switch, if required
        }
    }
}

int LoRaManager::setupLoRa() {
    txQueue = xQueueCreate(
        8,
        sizeof(TxMessage)
    );

    if (txQueue == nullptr) {
        LOG_E(TAG, "Failed to create TX queue");
        return -1;
    }

    loraSPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_NSS);
    statsStartTime = millis(); // Start the timer for duty cycle statistics.

    // Timers
    ackTimer = xTimerCreate("ackTimer", pdMS_TO_TICKS(2000), pdFALSE, nullptr, ackTimerCallback);
    // CAD Timer
    // cadRxTimer = xTimerCreate("cadRxTimer", pdMS_TO_TICKS(30), pdTRUE, nullptr, cadRxTimerCallback);
    // rxTimeoutTimer = xTimerCreate("rxTimeoutTimer", pdMS_TO_TICKS(1500), pdFALSE, nullptr, rxTimeoutTimerCallback); // If the CAD alert was false
    if (ackTimer == nullptr) {
        LOG_E(TAG, "Failed to create ACK timer");
        return -2;
    }

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
    // loraModule.sleep();

    // if (cadRxTimer != nullptr) xTimerStart(cadRxTimer, 0); // Start the CAD cycle
}

void LoRaManager::queueMessage(uint8_t* data, size_t length, uint32_t targetAddress, uint8_t currentFragment, uint8_t totalFragment) {
    constexpr size_t MAX_DATA_LENGTH = PAYLOAD_SIZE - sizeof(PackageHeader);

    if (data == nullptr && length > 0) {
        LOG_E(TAG, "queueMessage: NULL data");
        return;
    }

    if (length > MAX_DATA_LENGTH) {
        LOG_W(TAG, "Payload too large: %u > %u", (unsigned)length, (unsigned)MAX_DATA_LENGTH);
        return;
    }

    if (txQueue == nullptr) {
        LOG_E(TAG, "TX queue not initialized");
        return;
    }

    TxMessage message{};

    message.length = length;
    message.targetAddress = targetAddress;
    message.currentFragment = currentFragment;
    message.totalFragment = totalFragment;

    if (length > 0) {
        memcpy(message.data, data, length);
    }

    if (xQueueSend(txQueue, &message, 0) != pdPASS) {
        LOG_W(TAG,"TX queue full - message dropped");
    }
}

void LoRaManager::sendMessage(uint8_t* data, size_t length, uint32_t targetAddress, uint8_t currentFragment, uint8_t totalFragment, PackageType packageType, bool isRetry, uint8_t sequenceNumber) {
    LOG_I(TAG, "Preparing to send data of length %d", length);
    // if (cadRxTimer != nullptr) xTimerStop(cadRxTimer, 0); // Stop CAD while transmitting

    if (data == nullptr && length > 0) {
        LOG_E(TAG, "sendMessage: NULL data");
        return;
    }

    if (length > (PAYLOAD_SIZE - sizeof(PackageHeader))) {
        LOG_E(TAG, "Data length exceeds payload size...");
        return;
    }

    // Do not interrupt a transmission already on the air.
    if (isTransmitting) {
        LOG_W(TAG, "TX already active, transmission deferred.");
        return;
    }

    /*
     * A retry must use exactly the same sequence number as the
     * original transmission. A new DATA packet gets a new sequence.
     */
    if (sequenceNumber == 0xFF) {
        if (isRetry) {
            sequenceNumber = lastSequenceNumber;
        } else {
            sequenceNumber = currentSequenceNumber++;
        }
    }

    if (packageType == PKG_DATA && targetAddress != BROADCAST_ADDRESS) {
        if (!isRetry) {
            // If the message is new (not resending), save the parameters
            if (length > 0) {
                memcpy(lastPayload, data, length);
            }
            lastPayloadLength = length;
            lastTargetAddress = targetAddress;
            lastCurrentFragment = currentFragment;
            lastTotalFragment = totalFragment;
            lastSequenceNumber = sequenceNumber;
            retryCount = 0;
        }

        waitingForAck = true;

        if (ackTimer != nullptr) {
            xTimerStop(ackTimer, 0);
            xTimerStart(ackTimer, 0);
        }
    }

    PackageHeader header{};
    header.senderAddress = SystemManager::getLoRaID();
    header.targetAddress = targetAddress;
    header.packageType = packageType;
    header.sequenceNumber = sequenceNumber;
    header.currentFragment = currentFragment;
    header.totalFragments = totalFragment;

    // Combine header into one message buffer
    uint8_t txBuffer[PAYLOAD_SIZE];
    memcpy(txBuffer, &header, sizeof(PackageHeader));

    if (length > 0) {
        memcpy(txBuffer + sizeof(PackageHeader), data, length);
    }

    // Air Time calculation for statistics and duty cycle measurement
    float airTime = loraModule.getTimeOnAir(sizeof(PackageHeader) + length) / 1000.0f;

    LOG_I(TAG, "TX to 0x%08X | Type: %d | Seq: %d | Air Time: %.2f ms | Package %d of %d",
          targetAddress, packageType, sequenceNumber, airTime, currentFragment, totalFragment);

    // if (cadRxTimer != nullptr) xTimerStop(cadRxTimer, 0);

    // 10% duty cycle hardware limitation
    uint32_t requiredOffTimeMs = (uint32_t)(airTime * 9.0f); // In 10 units 1 can used, 9 can't usable
    nextTxAllowedMillis = millis() + requiredOffTimeMs;
    LOG_I(TAG, "Duty Cycle (10%%) enforced: TX paused for %lu ms", requiredOffTimeMs);


    loraModule.standby();
    // isScanning = false;
    actionFlag = false;
    isTransmitting = true;

    int state = loraModule.startTransmit(txBuffer, sizeof(PackageHeader) + length);

    if (state != RADIOLIB_ERR_NONE) {
        LOG_E(TAG, "Transmit start failed: %d", state);
        isTransmitting = false;

        if (packageType == PKG_DATA && targetAddress != BROADCAST_ADDRESS) {
            waitingForAck = false;
            if (ackTimer != nullptr) {
                xTimerStop(ackTimer, 0);
            }
        }

        startReceive(); // Return to receive mode if transmission fails.
    } else {
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
    /*
     * Only start a new transmission when the radio is idle.
     * DATA packets are taken from the FreeRTOS queue.
     */
    if (!isTransmitting && !waitingForAck && millis() >= nextTxAllowedMillis) {
        TxMessage message{};

        if (txQueue != nullptr &&
            xQueueReceive(txQueue, &message, 0) == pdPASS) {

            sendMessage(message.data,
                        message.length,
                        message.targetAddress,
                        message.currentFragment,
                        message.totalFragment,
                        PKG_DATA);
        }
    }

    if (!isTransmitting && !waitingForAck && heartbeatPending && millis() >= nextTxAllowedMillis) {
        heartbeatPending = false;
        sendHeartbeat(); // Sends a discovery/heartbeat message to broadcast
    }

    // Delete the inactive neighbors (That device has been inactive for heartbeat interval).
    unsigned long currentMillis = millis();
    uint32_t timeoutMs = heartbeatIntervalSeconds * 2500UL;

    for (uint8_t i = 0; i < neighborCount;) {
        if (currentMillis - neighbors[i].lastSeenMillis > timeoutMs){
            LOG_I(TAG, "Neighbor timeout, removed: 0x%08X", neighbors[i].senderAddress);
            for (uint8_t j = i; j < neighborCount - 1; j++){
                neighbors[j] = neighbors[j + 1];
            }
            neighborCount--;
        } else {
            i++;
        }
    }

    // If the 2 seconds elapsed, and not received ACK type package
    if (ackTimeoutPending) {
        ackTimeoutPending = false;
        if (waitingForAck) {
            if (retryCount < MAX_RETRIES) {
                retryCount++;
                LOG_W(TAG, "ACK timeout! Retrying send message to 0x%08X (Attempt %d/%d)", lastTargetAddress, retryCount, MAX_RETRIES);
                sendMessage(lastPayload, lastPayloadLength, lastTargetAddress, lastCurrentFragment, lastTotalFragment, PKG_DATA, true, lastSequenceNumber);
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
    //     rxTimeoutPending = false;
    //     LOG_W(TAG, "RX Timeout: False CAD alarm. Going back to sleep.");
    //     startReceive(); // Back to 'sleep'
    // }

    // Async CAD start
    // if (cadCheckPending) {
    //     cadCheckPending = false;

    //     loraModule.standby();
    //     isScanning = true; // Indicate that scanning started
    //     int state = loraModule.startChannelScan(); // NON blocking, means continue!

    //     if (state != RADIOLIB_ERR_NONE) {
    //         LOG_E(TAG, "CAD Start failed: %d", state);
    //         isScanning = false;
    //         startReceive();
    //     }
    // }

    if (!actionFlag) return;

    actionFlag = false; // Reset the flag to avoid missing future events.

    // if (isScanning) {
        // A) CAD scan finished in the background
        // isScanning = false;
        // int cadResult = loraModule.getChannelScanResult(); // Get result

        // if (cadResult == RADIOLIB_LORA_DETECTED) {
        //     LOG_I(TAG, "CAD: Activity detected! Waking up receiver...");
        //     xTimerStop(cadRxTimer, 0);
        //     loraModule.startReceive();
        //     xTimerStart(rxTimeoutTimer, 0);
        // } else {
        //     startReceive(); // Air is empty, go back to sleep
        // }
    //} else if (isTransmitting) {
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

        // Error handle on length greater than the limit
        if (len > PAYLOAD_SIZE) {
            LOG_W(TAG, "RX packet too large: %u bytes", (unsigned)len);
            loraModule.finishReceive();
            startReceive();
            return;
        }

        uint8_t rxBuffer[PAYLOAD_SIZE];

        int state = loraModule.readData(rxBuffer, len);

        if (state == RADIOLIB_ERR_NONE && len >= sizeof(PackageHeader)) {
            PackageHeader header{};
            memcpy(&header, rxBuffer, sizeof(PackageHeader));

            uint8_t* payload = rxBuffer + sizeof(PackageHeader);
            size_t payloadLength = len - sizeof(PackageHeader);

            LOG_I(TAG, "RX from 0x%08X, RSSI: %f, Type: %d",
                  header.senderAddress, loraModule.getRSSI(), header.packageType);

            // The received package is for BROADCAST or for this device
            bool packageIsForMe = (header.targetAddress == BROADCAST_ADDRESS ||
                                   header.targetAddress == (uint32_t)SystemManager::getLoRaID());

            /*
             * Heartbeat/discovery is the only packet that carries the
             * username, color and optionally coordinates over the air.
             */
            if (header.packageType == PKG_HEARTBEAT &&
                (payloadLength == sizeof(DiscoveryPayload) || payloadLength == sizeof(DiscoveryPayload) - 8)) {

                DiscoveryPayload discovery{};
                // Set 0.0 by default, if location sharing turned off.
                discovery.latitude = 0.0f;
                discovery.longitude = 0.0f;

                memcpy(&discovery, payload, payloadLength);
                discovery.username[sizeof(discovery.username) - 1] = '\0';

                updateNeighbor(header.senderAddress,
                               discovery.username,
                               discovery.colorR,
                               discovery.colorG,
                               discovery.colorB,
                               discovery.latitude,
                               discovery.longitude,
                               loraModule.getRSSI());
            }

            if (!packageIsForMe) {
                LOG_I(TAG, "Ignored package: Different target address! (0x%08X)", header.targetAddress);
            }
            // The received package is for BROADCAST or for this device
            else {
                // If the message is an ACK package.
                if (header.packageType == PKG_ACK &&
                    waitingForAck &&
                    header.senderAddress == lastTargetAddress &&
                    payloadLength == sizeof(AckPayload)) {

                    AckPayload ack{};
                    memcpy(&ack, payload, sizeof(AckPayload));

                    if (ack.sequenceNumber == lastSequenceNumber &&
                        ack.currentFragment == lastCurrentFragment) {

                        LOG_I(TAG, "ACK received from 0x%08X! Message delivered successfully.", header.senderAddress);
                        waitingForAck = false;

                        if (ackTimer != nullptr) {
                            xTimerStop(ackTimer, 0); // Stop the ACK timer on success.
                        }

                        // Push BLE message that shows the success.
                        char successMsg[50];
                        snprintf(successMsg, sizeof(successMsg), "ACK_OK;%08X", header.senderAddress);
                        BLEManager::pushMessage(successMsg);
                    } else {
                        LOG_W(TAG, "ACK mismatch: got Seq:%u Frag:%u, expected Seq:%u Frag:%u",
                              ack.sequenceNumber, ack.currentFragment,
                              lastSequenceNumber, lastCurrentFragment);
                    }
                }

                // Process DATA packets if they are targeted to this device OR are Broadcasts
                if (header.packageType == PKG_DATA &&
                    (header.targetAddress == (uint32_t)SystemManager::getLoRaID() || 
                     header.targetAddress == BROADCAST_ADDRESS)) {

                    bool duplicate = isDuplicatePacket(header.senderAddress,
                                                       header.sequenceNumber,
                                                       header.currentFragment);

                    // If the message has been received is for this device (P2P communication), send back an ACK type message.
                    if (header.targetAddress != BROADCAST_ADDRESS) {
                        LOG_I(TAG, "P2P type message received, sending back ACK to 0x%08X", header.senderAddress);

                        AckPayload ack{};
                        ack.sequenceNumber = header.sequenceNumber;
                        ack.currentFragment = header.currentFragment;

                        sendMessage(reinterpret_cast<uint8_t*>(&ack),
                                    sizeof(AckPayload),
                                    header.senderAddress,
                                    header.currentFragment,
                                    header.totalFragments,
                                    PKG_ACK,
                                    false,
                                    header.sequenceNumber);
                    } else {
                        LOG_I(TAG, "Broadcast message received, ACK ignored.");
                    }

                    /*
                     * If the ACK was lost, the sender may retransmit the
                     * same packet. ACK it again, but do not forward the
                     * duplicate to BLE.
                     */
                    if (duplicate) {
                        LOG_W(TAG, "Duplicate DATA ignored: 0x%08X Seq:%u Frag:%u",
                              header.senderAddress,
                              header.sequenceNumber,
                              header.currentFragment);
                    } else {
                        rememberPacket(header.senderAddress,
                                       header.sequenceNumber,
                                       header.currentFragment);
                    }

                    if (!duplicate && payloadLength > 0) {
                        char payloadString[PAYLOAD_SIZE];
                        size_t copyLength = (payloadLength < PAYLOAD_SIZE) ? payloadLength : PAYLOAD_SIZE - 1; // Ensure null-termination

                        memcpy(payloadString, payload, copyLength);
                        payloadString[copyLength] = '\0'; // Null-terminate the string

                        if (strncmp(payloadString, "KEY_REQ;", 8) == 0 || strncmp(payloadString, "KEY_RESP;", 9) == 0) {
                            char keyNotifyBuffer[PAYLOAD_SIZE + 20];
                            const char* separator = strchr(payloadString, ';');

                            if (separator != nullptr) {
                                int typeLength = separator - payloadString;
                                const char* pubKey = separator + 1;

                                snprintf(keyNotifyBuffer, sizeof(keyNotifyBuffer), "%.*s;%08X;%s", typeLength, payloadString, header.senderAddress, pubKey);
                                LOG_I(TAG, "Received KEY package: %s", keyNotifyBuffer);
                                bool isBroadcast = (header.targetAddress == BROADCAST_ADDRESS);
                                if (!BLEManager::isConnected() || !isBroadcast) {
                                    HapticManager::playEffect(52);
                                } else {
                                    LOG_I(TAG, "Haptics not played, because there is a connected device or the message was broadcast.");
                                }
                                BLEManager::pushMessage(keyNotifyBuffer, isBroadcast);
                            }
                        } else {
                            char formattedString[PAYLOAD_SIZE + 80]; // Extra space for formatting
                            time_t now;
                            time(&now);

                            // FAIL-SAFE: 1704067200 = 2024. 01. 1
                            // If the ESP time is less than the FAIL-SAFE time, there it is outdated. Set it to 0.
                            long safeTimestamp = (now < 1704067200) ? 0 : (long)now;

                            // Check if the target address was broadcast.
                            bool isBroadcast = (header.targetAddress == BROADCAST_ADDRESS);

                            // Format generation: SENDER_ADDRESS;SENDER_USERNAME;COLOR_HEX;TARGET_ADDRESS;CURRENT_FRAGMENT;TOTAL_FRAGMENT;TIMESTAMP;RSSI;PAYLOAD
                            const char* senderUsername = "Unknown";
                            uint8_t r = 0, g = 136, b = 255; // Default Light Blue color

                            for (uint8_t i = 0; i < neighborCount; ++i) {
                                if (neighbors[i].senderAddress == header.senderAddress) {
                                    senderUsername = neighbors[i].senderUsername;
                                    r = neighbors[i].colorR;
                                    g = neighbors[i].colorG;
                                    b = neighbors[i].colorB;
                                    break;
                                }
                            }

                            char colorHex[7];
                            snprintf(colorHex, sizeof(colorHex), "%02X%02X%02X", r, g, b);

                            snprintf(formattedString, sizeof(formattedString), "%08X;%s;%s;%08X;%d;%d;%ld;%.2f;%s",
                                    header.senderAddress,
                                    senderUsername,
                                    colorHex,
                                    header.targetAddress,
                                    header.currentFragment,
                                    header.totalFragments,
                                    safeTimestamp,
                                    loraModule.getRSSI(),
                                    payloadString);

                            LOG_I(TAG, "Received DATA package: %s", formattedString);
                            // Play haptics if the message was P2P or a client was connected.
                            (!BLEManager::isConnected() || !isBroadcast) ? HapticManager::playEffect(52) :
                            LOG_I(TAG, "Haptics not played, because there is a connected device or the message was broadcast.");
                            BLEManager::pushMessage(formattedString, isBroadcast); // Forward the message to the BLE Manager to notify connected clients.
                        }
                    }
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

void LoRaManager::updateNeighbor(uint32_t senderAddress, const char* username, uint8_t colorR, uint8_t colorG, uint8_t colorB, float latitude, float longitude, float rssi) {
    time_t now;
    time(&now);

    // FAIL-SAFE: 1704067200 = 2024. 01. 1
    // If the ESP time is less than the FAIL-SAFE time, there it is outdated. Set it to 0.
    long safeTimestamp = (now < 1704067200) ? 0 : (long)now;
    unsigned long currentMillis = millis(); // Timestamp used for internal timeout

    // Check if the sender is already in the neighbors list
    for (uint8_t i = 0; i < neighborCount; i++) {
        if (neighbors[i].senderAddress == senderAddress) {
            strncpy(neighbors[i].senderUsername, username, sizeof(neighbors[i].senderUsername) - 1);
            neighbors[i].senderUsername[sizeof(neighbors[i].senderUsername) - 1] = '\0';
            neighbors[i].colorR = colorR;
            neighbors[i].colorG = colorG;
            neighbors[i].colorB = colorB;
            neighbors[i].latitude = latitude;
            neighbors[i].longitude = longitude;
            neighbors[i].timestamp = safeTimestamp; // Update timestamp (last seen)
            neighbors[i].lastSeenMillis = currentMillis;
            neighbors[i].rssi = rssi; // Update RSSI value (signal strength)
            return;
        }
    }

    // If not found, add the neighbor to the list, if there is space left
    if (neighborCount < MAX_NEIGHBORS) {
        neighbors[neighborCount].senderAddress = senderAddress;
        strncpy(neighbors[neighborCount].senderUsername, username, sizeof(neighbors[neighborCount].senderUsername) - 1);
        neighbors[neighborCount].senderUsername[sizeof(neighbors[neighborCount].senderUsername) - 1] = '\0';
        neighbors[neighborCount].colorR = colorR;
        neighbors[neighborCount].colorG = colorG;
        neighbors[neighborCount].colorB = colorB;
        neighbors[neighborCount].latitude = latitude;
        neighbors[neighborCount].longitude = longitude;
        neighbors[neighborCount].rssi = rssi;
        neighbors[neighborCount].timestamp = safeTimestamp;
        neighbors[neighborCount].lastSeenMillis = currentMillis;
        neighborCount++;
        LOG_I(TAG, "New neighbor added: 0x%08X (%s) with RSSI: %f", senderAddress, username, rssi);
    } else {
        LOG_W(TAG, "Neighbors list full. Cannot add new neighbor: 0x%08X", senderAddress);
    }
}

bool LoRaManager::getNeighbors(DiscoveryInfo* output, uint8_t maxCount, uint8_t& count) {
    if (output == nullptr || maxCount == 0) {
        count = 0;
        return false;
    }

    count = neighborCount;
    if (count > maxCount) {
        count = maxCount;
    }

    memcpy(output, neighbors, count * sizeof(DiscoveryInfo));
    return true;
}

bool LoRaManager::isDuplicatePacket(uint32_t senderAddress, uint8_t sequenceNumber, uint8_t currentFragment) {
    for (uint8_t i = 0; i < receivedCacheCount; ++i) {
        if (receivedCache[i].senderAddress == senderAddress &&
            receivedCache[i].sequenceNumber == sequenceNumber &&
            receivedCache[i].currentFragment == currentFragment) {
            return true;
        }
    }

    return false;
}

void LoRaManager::rememberPacket(uint32_t senderAddress, uint8_t sequenceNumber, uint8_t currentFragment) {
    if (isDuplicatePacket(senderAddress, sequenceNumber, currentFragment)) {
        return;
    }

    ReceivedPacket packet{};
    packet.senderAddress = senderAddress;
    packet.sequenceNumber = sequenceNumber;
    packet.currentFragment = currentFragment;

    if (receivedCacheCount < MAX_RECEIVED_CACHE) {
        receivedCache[receivedCacheCount++] = packet;
        return;
    }

    for (uint8_t i = 1; i < MAX_RECEIVED_CACHE; ++i) {
        receivedCache[i - 1] = receivedCache[i];
    }

    receivedCache[MAX_RECEIVED_CACHE - 1] = packet;
}

void LoRaManager::sendHeartbeat() {
    DiscoveryPayload discovery{};

    const char* username = SystemManager::getUsername();
    if (username != nullptr) {
        strncpy(discovery.username,
                username,
                sizeof(discovery.username) - 1);
    }
    discovery.username[sizeof(discovery.username) - 1] = '\0';

    const char* color = SystemManager::getColor();

    if (color != nullptr && strlen(color) == 6) {
        char r[3] = { color[0], color[1], '\0' };
        char g[3] = { color[2], color[3], '\0' };
        char b[3] = { color[4], color[5], '\0' };

        discovery.colorR = (uint8_t)strtoul(r, nullptr, 16);
        discovery.colorG = (uint8_t)strtoul(g, nullptr, 16);
        discovery.colorB = (uint8_t)strtoul(b, nullptr, 16);
    } else {
        discovery.colorR = 0;
        discovery.colorG = 136;
        discovery.colorB = 255;
    }

    float lat, lon;
    SystemManager::getLocation(lat, lon);

    discovery.latitude = lat;
    discovery.longitude = lon;

    // Calculate the package length (If NO_LOC ran, dont send the 8 byte 0)
    size_t payloadSizeToTransmit = sizeof(DiscoveryPayload);
    if (lat == 0.0f && lon == 0.0f) payloadSizeToTransmit -= 8;

    sendMessage(reinterpret_cast<uint8_t*>(&discovery),
                payloadSizeToTransmit,
                BROADCAST_ADDRESS,
                1,
                1,
                PKG_HEARTBEAT,
                false);
}

void LoRaManager::startHeartbeat(uint16_t intervalSeconds) {
    heartbeatIntervalSeconds = intervalSeconds;

    if (heartbeatTimer != nullptr) {
        xTimerStop(heartbeatTimer, 0);
        xTimerDelete(heartbeatTimer, 0);
    }
    heartbeatTimer = xTimerCreate("HeartbeatTimer", pdMS_TO_TICKS(intervalSeconds * 1000), pdTRUE, nullptr, heartbeatTimerCallback);

    if (heartbeatTimer != nullptr) {
        xTimerStart(heartbeatTimer, 0);
        heartbeatPending = true;
    }

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