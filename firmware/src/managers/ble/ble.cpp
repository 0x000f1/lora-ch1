#include "ble.h"
#include "managers/system/system_manager.h"
#include "utils/log_helper.h"
#include <NimBLEDevice.h>
#include "managers/lora/lora.h"
#include "managers/ble/ble.h"
#include <esp_bt.h>

#define TAG "BLE" 

static NimBLEServer* server = nullptr;
static NimBLECharacteristic* dataCharacteristic = nullptr;
static NimBLECharacteristic* controlCharacteristic = nullptr;

TimerHandle_t BLEManager::pairingTimer = nullptr;
volatile bool BLEManager::shutdownPending = false;
static bool isRadioSleeping = false; // Track the state of the radio

bool BLEManager::isBLEActive() {
    return NimBLEDevice::isInitialized() && 
        (NimBLEDevice::getAdvertising()->isAdvertising() || 
        (server != nullptr && server->getConnectedCount() > 0));
}

void BLEManager::stopBLE() {
    if (pairingTimer != nullptr) xTimerStop(pairingTimer, 0);
    LOG_I(TAG, "Stopping advertising and trying to sleep the BLE hardware...");
    NimBLEDevice::stopAdvertising();

    // Disconnect all peers for safety.
    if (server != nullptr) {
        std::vector<uint16_t> peers = server->getPeerDevices();
        for (auto& peer : peers) {
            server->disconnect(peer);
        }
    }

    vTaskDelay(pdMS_TO_TICKS(150)); // 100 ms delay to wait clients disconnection.
    // NimBLEDevice::deinit(false); // Keep the data, disconnect the BLE module.
    esp_bt_controller_disable();
    isRadioSleeping = true;

    LOG_I(TAG, "BLE is turned OFF.");
}

void BLEManager::handleFlags() {
    if (shutdownPending) {
        shutdownPending = false;
        stopBLE();
        LOG_I(TAG, "BLE sleep completed. Setting power profile to BATTERY_SAVER");
        SystemManager::setPowerProfile(PowerProfile::BATTERY_SAVER);
    }
}

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
        LOG_I(TAG, "Client disconnected. Reason: %d. Press button to start advertising.", reason);
        BLEManager::shutdownPending = true;
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
                std::string response = "";

                for (uint8_t i = 0; i < count; i++) {
                    char responseBuffer[64];
                    snprintf(responseBuffer, sizeof(responseBuffer), 
                                            "%08X;%.2f;%lu|",
                                            list[i].senderAddress, 
                                            list[i].rssi, 
                                            list[i].timestamp);
                    response += responseBuffer;
                }
                nimBleChar->setValue(response);
            }
            nimBleChar->notify();
        }
        else if (strncmp(cmd, "SET_PWR;", 8) == 0) {
            const char* profileStr = cmd + 8;
            if (strcmp(profileStr, "BATTERY_SAVER") == 0) {
                SystemManager::setPowerProfile(PowerProfile::BATTERY_SAVER);
                nimBleChar->setValue("PWR_OK");
            } else if (strcmp(profileStr, "BALANCED") == 0) {
                SystemManager::setPowerProfile(PowerProfile::BALANCED);
                nimBleChar->setValue("PWR_OK");
            } else if (strcmp(profileStr, "PERFORMANCE") == 0) {
                SystemManager::setPowerProfile(PowerProfile::PERFORMANCE);
                nimBleChar->setValue("PWR_OK");
            } else {
                LOG_W(TAG, "Unknown power profile requested: %s", profileStr);
                nimBleChar->setValue("PWR_ERR");
            }
            nimBleChar->notify();
        }
        else if (strcmp(cmd, "GET_BAT") == 0) {
            uint8_t batLevel = BatteryManager::getBatteryPercentage();
            bool isCharging = BatteryManager::isCharging();

            char response[30];
            snprintf(response, sizeof(response), "BAT;%d;%d", batLevel, isCharging);
            
            nimBleChar->setValue(std::string(response));
            nimBleChar->notify();
            LOG_I(TAG, "Battery percentage: %d | Charging: %d", (uint8_t)batLevel, isCharging);
        }
        else if (strcmp(cmd, "GET_USR") == 0) {
            String username = SystemManager::getUsername();
            char response[64];
            snprintf(response, sizeof(response), "USR;%s", username.c_str());
            
            nimBleChar->setValue(std::string(response));
            nimBleChar->notify();
            LOG_I(TAG, "Sent username to client: %s", username.c_str());
        }
        else if (strncmp(cmd, "SET_USR;", 8) == 0) {

            const char* payloadStr = cmd + 8;

            SystemManager::setUsername(payloadStr);
            
            nimBleChar->setValue("USR_OK");
            nimBleChar->notify();
        }
        else if (strcmp(cmd, "GET_COL") == 0) {
            String color = SystemManager::getColor();
            char response[20];
            snprintf(response, sizeof(response), "COL;%s", color.c_str());
            
            nimBleChar->setValue(std::string(response));
            nimBleChar->notify();
            LOG_I(TAG, "Sent color to client: %s", color.c_str());
        }
        else if (strncmp(cmd, "SET_COL;", 8) == 0) {

            const char* payloadStr = cmd + 8;

            SystemManager::setColor(payloadStr);
            
            nimBleChar->setValue("COL_OK");
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
    LOG_I(TAG, "Pairing mode timeout (60s). Shutting down BLE.");
    SystemManager::setPowerProfile(PowerProfile::BATTERY_SAVER);
    BLEManager::shutdownPending = true;
}

// Declare the callback entities statically
static serverStatusCallback servCallbacks;
static dataCharStatusCallbacks dataCallbacks;
static controlCharStatusCallbacks ctrlCallbacks;

int BLEManager::setupBLE() {
    if (NimBLEDevice::isInitialized()) return 0;

    LOG_I(TAG, "Initializing BLE stack and allocating memory.");
    NimBLEDevice::init(SystemManager::getDeviceName());
    NimBLEDevice::setPower(ESP_PWR_LVL_N0);
    // Set the MTU to 512: Able to notify the clients with the full data.
    // By default the MTU is 23 byte, and only send the notify this long.
    NimBLEDevice::setMTU(512);

    server = NimBLEDevice::createServer();
    if (!server) return 1; // Server start error
    server->setCallbacks(&servCallbacks);

    NimBLEService* service = server->createService(SystemManager::getServiceUUID());
    if (!service) return 2; // Service start error
    
    // DATA characteristic for sending/receiving messages
    dataCharacteristic = service->createCharacteristic(
        SystemManager::getDataCharUUID(),
        NIMBLE_PROPERTY::READ | 
        NIMBLE_PROPERTY::WRITE | 
        NIMBLE_PROPERTY::WRITE_NR | 
        NIMBLE_PROPERTY::NOTIFY
    );
    dataCharacteristic->setCallbacks(&dataCallbacks);
    
    // CONTROL characteristic for receiving control commands
    controlCharacteristic = service->createCharacteristic(
        SystemManager::getControlCharUUID(),
        NIMBLE_PROPERTY::READ |
        NIMBLE_PROPERTY::WRITE | 
        NIMBLE_PROPERTY::WRITE_NR | 
        NIMBLE_PROPERTY::NOTIFY
    );
    controlCharacteristic->setCallbacks(&ctrlCallbacks);

    service->start();

    NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
    advertising->setName(SystemManager::getDeviceName());
    advertising->addServiceUUID(SystemManager::getServiceUUID());
    advertising->enableScanResponse(true);

    advertising->setMinInterval(256); // ~160ms
    advertising->setMaxInterval(512); // ~320ms

    if (pairingTimer == nullptr) {
        pairingTimer = xTimerCreate("pairingTimer", pdMS_TO_TICKS(60000), pdFALSE, nullptr, pairingTimerCallback);
    }
    
    LOG_I(TAG, "BLE setup completed! (Advertising is OFF by default. Press button!)");
    esp_bt_controller_disable();
    isRadioSleeping = true;

    return 0;
}

void BLEManager::startPairingMode() {
    if (!NimBLEDevice::isInitialized()) {
        setupBLE();
    }

    // Wake up the radio if it was sleeping.
    if (isRadioSleeping) {
        LOG_I(TAG, "Waking up BLE hardware...");
        esp_bt_controller_enable(ESP_BT_MODE_BLE);
        isRadioSleeping = false;
        vTaskDelay(pdMS_TO_TICKS(50));
    }

    if (server != nullptr && server->getConnectedCount() > 0) {
        LOG_W(TAG, "Already connected to a client. Pairing mode ignored.");
        return;
    }

    NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();

    if (advertising->start()) {
        LOG_I(TAG, "Pairing mode started! Visible as: %s", SystemManager::getDeviceName());
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
    if (NimBLEDevice::isInitialized()) {
        NimBLEDevice::stopAdvertising();
        LOG_I(TAG, "Pairing mode and advertising stopped.");
    }
}

void BLEManager::pushMessage(const char* message) {
    if (server != nullptr && dataCharacteristic != nullptr && server->getConnectedCount() > 0) {
        dataCharacteristic->setValue(std::string(message));
        dataCharacteristic->notify(); // Notify all connected clients
        LOG_I(TAG, "Sent notify: %s", message);
    } else {
        LOG_W(TAG, "No clients connected. Message not sent: %s", message);
    }
}