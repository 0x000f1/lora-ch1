#include "ble.h"
#include "system_manager.h"
#include "utils/log_helper.h"
#include <NimBLEDevice.h>
#include "lora.h"

#define TAG "BLE" 

static NimBLEServer* server = nullptr;
static NimBLECharacteristic* characteristic = nullptr;

// Callbacks
class serverStatusCallback : public NimBLEServerCallbacks {
    // Handle client connections and disconnections, and update connection parameters for better performance.
    void onConnect(NimBLEServer* nimBleServer, NimBLEConnInfo& connInfo) override {
        LOG_I(TAG, "Client connected: %s", connInfo.getAddress().toString().c_str());
        nimBleServer->updateConnParams(connInfo.getConnHandle(), 24, 48, 0, 180);
    }
    // Handle client disconnections and restart advertising to allow new clients to connect.
    void onDisconnect(NimBLEServer* nimBleServer, NimBLEConnInfo& connInfo, int reason) override {
        LOG_I(TAG, "Client disconnected.");
        NimBLEDevice::startAdvertising();
    }
};

class charStatusCallbacks : public NimBLECharacteristicCallbacks {
    // Handle characteristic write event, and log the new value when a client writes to the characteristic.
    void onWrite(NimBLECharacteristic* nimBleChar, NimBLEConnInfo& connInfo) override {
        LOG_I(TAG, "Characteristic written by client: %s", nimBleChar->getValue().c_str());
        LoRaManager::sendMessage(nimBleChar->getValue().c_str()); // Forward the new value to the LoRa Manager to send it over LoRa.
    }
};

int BLEManager::setupBLE() {
    NimBLEDevice::init(SystemManager::getDeviceName().c_str());

    server = NimBLEDevice::createServer();
    if (server == nullptr) {
        LOG_E(TAG, "Failed to create BLE server");
        return 1; // Server start error
    }
    server->setCallbacks(new serverStatusCallback());

    NimBLEService* service = server->createService(SystemManager::getServiceUUID().c_str());
    if (service == nullptr) {
        LOG_E(TAG, "Failed to create BLE service");
        return 2; // Service start error
    }
    characteristic = service->createCharacteristic(
        SystemManager::getCharUUID().c_str(),
        NIMBLE_PROPERTY::READ | 
        NIMBLE_PROPERTY::WRITE | 
        NIMBLE_PROPERTY::NOTIFY
    );
    if (characteristic == nullptr) {
        LOG_E(TAG, "Failed to create BLE characteristic");
        return 3; // Characteristic creation error
    }
    
    characteristic->setCallbacks(new charStatusCallbacks());
    characteristic->setValue("Sample value"); // Initial value for testing

    service->start();

    NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
    advertising->setName(SystemManager::getDeviceName().c_str());
    advertising->addServiceUUID(SystemManager::getServiceUUID().c_str());
    advertising->enableScanResponse(true);
    if (!advertising->start()) { 
        LOG_E(TAG, "Failed to start BLE advertising");
        return 4; // Advertising start error
    }
    LOG_I(TAG, "BLE setup completed!");
    return 0;
}

void BLEManager::pushMessage(const char* message) {
    if (server->getConnectedCount() > 0) {
        characteristic->setValue(message);
        characteristic->notify(); // Notify all connected clients
        LOG_I(TAG, "Sent notify: %s", message);
    } else {
        LOG_W(TAG, "No clients connected. Message not sent: %s", message);
    }
}