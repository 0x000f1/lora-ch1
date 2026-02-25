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

SPIClass loraSPI(FSPI); // FSPI = SPI2 | Use the FSPI for custom pin configuration.
SX1278 loraModule = new Module(LORA_NSS, LORA_DIO0, LORA_RST, RADIOLIB_NC, loraSPI);

volatile bool actionFlag = false; // Interrupt flag to show receive/transmit events.
bool isTransmitting = false;      // Current state: true = waiting for transmission to finish, false = waiting for package.

uint8_t LoRaManager::currentSequenceNumber = 0; // Initialize sequence number.

// Interrupt callback stored in RAM to ensure fast access.
void ICACHE_RAM_ATTR LoRaManager::setFlag() {
    actionFlag = true;
}

int LoRaManager::setupLoRa() {
    loraSPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_NSS);
    
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
    int state = loraModule.startReceive();
    if (state == RADIOLIB_ERR_NONE) {
        isTransmitting = false;
        LOG_I(TAG, "Listening for incoming messages...");
    } else {
        LOG_E(TAG, "Starting receive failed: %d", state);
    }
}

void LoRaManager::sendMessage(uint8_t* data, size_t length, uint32_t targetAddress, PackageType packageType) {
    LOG_I(TAG, "Preparing to send data of length %d", length);
    
    // There will be used a CAD (Channel Activity Detection) before transmission to avoid collisions. If the channel is busy, it will wait and retry.
    
    if (length > (PAYLOAD_SIZE - sizeof(PackageHeader))) {
        // @todo Here comes later the fragmentation logic
        LOG_E(TAG, "Data length exceeds payload size...");
        return;
    }

    PackageHeader header;
    header.senderAddress = SystemManager::getLoRaID();
    header.targetAddress = targetAddress;
    header.packageType = packageType;
    header.sequenceNumber = currentSequenceNumber++;
    header.currentFragment = 0;
    header.totalFragments = 1;

    // Combine header into one message buffer
    uint8_t txBuffer[PAYLOAD_SIZE];
    memcpy(txBuffer, &header, sizeof(PackageHeader));
    memcpy(txBuffer + sizeof(PackageHeader), data, length);

    LOG_I(TAG, "Starting transmission to 0x%02X, Type: %d", targetAddress, packageType);

    isTransmitting = true;
    int state = loraModule.startTransmit(txBuffer, sizeof(PackageHeader) + length);
    
    if (state != RADIOLIB_ERR_NONE) {
        LOG_E(TAG, "Transmit start failed: %d", state);
        startReceive(); // Return to receive mode if transmission fails.
    }
}

void LoRaManager::handleFlags() {
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
            PackageHeader* header = (PackageHeader*)rxBuffer;
            uint8_t* payload = rxBuffer + sizeof(PackageHeader);
            size_t payloadLength = len - sizeof(PackageHeader);

            LOG_I(TAG, "RX from 0x%08X, RSSI: %f, Type: %d", header->senderAddress, loraModule.getRSSI(), header->packageType);
            
            // Convert to char array if it's a data package and forward to BLE Manager.
            if (header->packageType == PKG_DATA && payloadLength > 0) {
                char str[PAYLOAD_SIZE];
                size_t copyLength = (payloadLength < PAYLOAD_SIZE) ? payloadLength : PAYLOAD_SIZE - 1; // Ensure null-termination
                
                memcpy(str, payload, copyLength);
                str[copyLength] = '\0'; // Null-terminate the string
                LOG_I(TAG, "Received DATA package: %s", str);

                BLEManager::pushMessage(str); // Forward the message to the BLE Manager to notify connected clients.
            }
        } else if (state == RADIOLIB_ERR_CRC_MISMATCH) {
            LOG_W(TAG, "CRC Error!");
        } else {
            LOG_E(TAG, "Receive failed, code: %d", state);
        }
    }
}