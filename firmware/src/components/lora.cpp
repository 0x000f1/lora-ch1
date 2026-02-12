#include "lora.h"
#include "utils/log_helper.h"
#include "components/ble.h"
#include <SPI.h>
#include <RadioLib.h>

#define TAG "LORA"

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

void LoRaManager::sendMessage(String msg) {
    LOG_I(TAG, "Preparing to send: %s", msg.c_str());
    
    // There will be used a CAD (Channel Activity Detection) before transmission to avoid collisions. If the channel is busy, it will wait and retry.
    
    isTransmitting = true;
    int state = loraModule.startTransmit(msg);
    
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
        String str;
        int state = loraModule.readData(str);

        if (state == RADIOLIB_ERR_NONE) {
            LOG_I(TAG, "Received: %s [RSSI: %f]", str.c_str(), loraModule.getRSSI());
            BLEManager::pushMessage(str.c_str()); // Forward the message to the BLE Manager to notify connected clients.
        } else if (state == RADIOLIB_ERR_CRC_MISMATCH) {
            LOG_W(TAG, "CRC Error!");
        } else {
            LOG_E(TAG, "Receive failed, code: %d", state);
        }
    }
}