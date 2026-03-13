#include "ble.h"
#include "managers/system/system_manager.h"
#include "utils/log_helper.h"
#include <NimBLEDevice.h>
#include "managers/lora/lora.h"
#include "managers/ble/ble.h"

#define TAG "BLE" 

static NimBLEServer* server = nullptr;
static NimBLECharacteristic* dataCharacteristic = nullptr;
static NimBLECharacteristic* controlCharacteristic = nullptr;

TimerHandle_t BLEManager::pairingTimer = nullptr;

// Callbacks
class serverStatusCallback : public NimBLEServerCallbacks {
    // Handle client connections and disconnections, and update connection parameters for better performance.
    void onConnect(NimBLEServer* nimBleServer, NimBLEConnInfo& connInfo) override {
        LOG_I(TAG, "Client connected: %s", connInfo.getAddress().toString().c_str());
        nimBleServer->updateConnParams(connInfo.getConnHandle(), 24, 48, 0, 180);
        BLEManager::stopPairingMode();
    }
    // Handle client disconnections and restart advertising to allow new clients to connect.
    void onDisconnect(NimBLEServer* nimBleServer, NimBLEConnInfo& connInfo, int reason) override {
        LOG_I(TAG, "Client disconnected. Press button to start advertising.");
    }
};

class controlCharStatusCallbacks : public NimBLECharacteristicCallbacks {
    // Handle control characteristic events (Batter, Neighbor, etc.)
    void onWrite(NimBLECharacteristic* nimBleChar, NimBLEConnInfo& connInfo) override {
        std::string rxValue = nimBleChar->getValue();
        const char* cmd = rxValue.c_str();

        LOG_I(TAG, "Control Characteristic written by client: %s", cmd);

        if (strcmp(cmd, "GET_NEI") == 0) {
            uint8_t count = 0;
            DiscoveryInfo* list = LoRaManager::getNeighbors(count);

            if (count == 0) {
                LOG_I(TAG, "No neighbors found.");
                nimBleChar->setValue("NO_NEI");
            } else {
                char responseBuffer[512] = {0};
                size_t offset = 0;

                for (uint8_t i = 0; i < count; i++) {
                    int written = snprintf(responseBuffer + offset, sizeof(responseBuffer) - offset, 
                                           "%08X,%.2f;%lu|",
                                           list[i].senderAddress, 
                                           list[i].rssi, 
                                           list[i].timestamp);
                    
                    if (written > 0 && offset + written < sizeof(responseBuffer)) {
                        offset += written;
                    } else {
                        break;
                    }
                }
                nimBleChar->setValue(responseBuffer);
            }
            nimBleChar->notify();
        }
        else if (strncmp(cmd, "SET_PWR;", 8) == 0) {
            
            const char* profileStr = cmd + 8;

            if (strcmp(profileStr, "BATTERY_SAVER") == 0) {
                BatteryManager::setPowerProfile(PowerProfile::BATTERY_SAVER);
                nimBleChar->setValue("PWR_OK");
            } else if (strcmp(profileStr, "BALANCED") == 0) {
                BatteryManager::setPowerProfile(PowerProfile::BALANCED);
                nimBleChar->setValue("PWR_OK");
            } else if (strcmp(profileStr, "PERFORMANCE") == 0) {
                BatteryManager::setPowerProfile(PowerProfile::PERFORMANCE);
                nimBleChar->setValue("PWR_OK");
            } else {
                LOG_W(TAG, "Unknown power profile requested: %s", profileStr);
                nimBleChar->setValue("PWR_ERR");
            }
            nimBleChar->notify();
        }
    }
};

class dataCharStatusCallbacks : public NimBLECharacteristicCallbacks {
    // Handle characteristic write event, and log the new value when a client writes to the characteristic.
    void onWrite(NimBLECharacteristic* nimBleChar, NimBLEConnInfo& connInfo) override {
        // Format parsing: SENDER_ADDRESS;CURRENT_FRAGMENT;TOTAL_FRAGMENT;PAYLOAD
        // Example:              FFFFFFFF;               1;             1;  Hello
        std::string bleValue = nimBleChar->getValue(); // Save the value to a local variable
        const char* value = bleValue.c_str();
        size_t totalLength = bleValue.length();
        LOG_I(TAG, "Characteristic written by client: %s", value);
        
        char* pEnd; // Helper constant for strtoul

        // 1. Getting the destination MAC address
        uint32_t targetAddress = strtoul(value, &pEnd, 16);
        if (pEnd == value || *pEnd != ';') {
            LOG_E(TAG, "Invalid BLE payload format: Target Address error!");
            return;
        }

        // 2. Getting the current fragment number
        const char* currentFragStart = pEnd + 1; // Jump after the ';'
        uint8_t currentFragment = strtoul(currentFragStart, &pEnd, 10);
        if (pEnd == currentFragStart || *pEnd != ';') {
            LOG_E(TAG, "Invalid BLE payload format: Current Fragment error!");
            return;
        }
        
        // 3. Getting the total fragment number
        const char* totalFragStart = pEnd + 1; // Jump after the ';'
        uint8_t totalFragment = strtoul(totalFragStart, &pEnd, 10);
        if (pEnd == totalFragStart || *pEnd != ';') {
            LOG_E(TAG, "Invalid BLE payload format: Total Fragments error!");
            return;
        }

        // 4. Getting the payload
        const char* payload = pEnd + 1; // Jump after the ';'
        size_t payloadLength = totalLength - (payload - value);
        
        LoRaManager::queueMessage((uint8_t*)payload, payloadLength, targetAddress, currentFragment, totalFragment); // Forward the new value to the LoRa Manager to send it over LoRa.
    }
};

void BLEManager::pairingTimerCallback(TimerHandle_t xTimer) {
    NimBLEDevice::stopAdvertising();
    LOG_I(TAG, "Pairing mode timeout (60s). Advertising stopped to save power and ensure security.");
}

void BLEManager::startPairingMode() {
    if (server->getConnectedCount() > 0) {
        LOG_W(TAG, "Already connected to a client. Pairing mode ignored.");
        return;
    }

    NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
    if (advertising->start()) {
        LOG_I(TAG, "Pairing mode started! Device is visible for 60 seconds.");
        if (pairingTimer != nullptr) {
            xTimerStart(pairingTimer, 0); // Start the callback timer to stop after 60 sec.
        }
    } else {
        LOG_E(TAG, "Failed to start advertising.");
    }
}

void BLEManager::stopPairingMode() {
    if (pairingTimer != nullptr) {
        xTimerStop(pairingTimer, 0);
    }
    NimBLEDevice::stopAdvertising();
    LOG_I(TAG, "Pairing mode and advertising stopped.");
}

// Declare the callback entities statically
static serverStatusCallback servCallbacks;
static dataCharStatusCallbacks dataCallbacks;
static controlCharStatusCallbacks ctrlCallbacks;

int BLEManager::setupBLE() {
    NimBLEDevice::init(SystemManager::getDeviceName().c_str());
    // Set the MTU to 512: Able to notify the clients with the full data.
    // By default the MTU is 23 byte, and only send the notify this long.
    NimBLEDevice::setMTU(512);

    server = NimBLEDevice::createServer();
    if (!server) return 1; // Server start error
    server->setCallbacks(&servCallbacks);

    NimBLEService* service = server->createService(SystemManager::getServiceUUID().c_str());
    if (!service) return 2; // Service start error
    
    // DATA characteristic for sending/receiving messages
    dataCharacteristic = service->createCharacteristic(
        SystemManager::getDataCharUUID().c_str(),
        NIMBLE_PROPERTY::READ | 
        NIMBLE_PROPERTY::WRITE | 
        NIMBLE_PROPERTY::NOTIFY
    );
    dataCharacteristic->setCallbacks(&dataCallbacks);
    
    // CONTROL characteristic for receiving control commands
    controlCharacteristic = service->createCharacteristic(
        SystemManager::getControlCharUUID().c_str(),
        NIMBLE_PROPERTY::READ |
        NIMBLE_PROPERTY::WRITE | 
        NIMBLE_PROPERTY::NOTIFY
    );
    controlCharacteristic->setCallbacks(&ctrlCallbacks);

    service->start();

    NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
    advertising->setName(SystemManager::getDeviceName().c_str());
    advertising->addServiceUUID(SystemManager::getServiceUUID().c_str());
    advertising->enableScanResponse(true);

    pairingTimer = xTimerCreate("pairingTimer", pdMS_TO_TICKS(60000), pdFALSE, nullptr, pairingTimerCallback);
    
    LOG_I(TAG, "BLE setup completed! (Advertising is OFF by default. Press button!)");
    return 0;
}

void BLEManager::pushMessage(const char* message) {
    if (server->getConnectedCount() > 0) {
        dataCharacteristic->setValue(message);
        dataCharacteristic->notify(); // Notify all connected clients
        LOG_I(TAG, "Sent notify: %s", message);
    } else {
        LOG_W(TAG, "No clients connected. Message not sent: %s", message);
    }
}