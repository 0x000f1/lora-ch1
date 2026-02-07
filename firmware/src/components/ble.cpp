#include "ble.h"
#include "../config.h"
#include <NimBLEDevice.h>

#define TAG "NimBLE" 

static NimBLEServer* server = nullptr;
static NimBLECharacteristic* characteristic = nullptr;

// Callbacks
class serverStatusCallback : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* nimBleServer, NimBLEConnInfo& connInfo) override {
        Serial.printf("[%s] Client connected: %s\n", TAG, connInfo.getAddress().toString().c_str());
        nimBleServer->updateConnParams(connInfo.getConnHandle(), 24, 48, 0, 180);
    }
    void onDisconnect(NimBLEServer* nimBleServer, NimBLEConnInfo& connInfo, int reason) override {
        Serial.printf("[%s] Client disconnected.\n", TAG);
        NimBLEDevice::startAdvertising();
    }
};

class charStatusCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* nimBleChar, NimBLEConnInfo& connInfo) override {
        Serial.printf("[%s] (%s): %s\n", TAG, nimBleChar->getUUID().toString().c_str(), nimBleChar->getValue().c_str());
    }
};

int setupBLE(const char* name) {
    NimBLEDevice::init(name);

    server = NimBLEDevice::createServer();
    if (server == nullptr) return 1; // Server start error
    server->setCallbacks(new serverStatusCallback());

    NimBLEService* service = server->createService(SERVICE_UUID);
    if (service == nullptr) return 2; // Service start error

    characteristic = service->createCharacteristic(
        CHARACTERISTIC_UUID,
        NIMBLE_PROPERTY::READ | 
        NIMBLE_PROPERTY::WRITE | 
        NIMBLE_PROPERTY::NOTIFY
    );
    if (characteristic == nullptr) return 3; // Characteristic creation error
    
    characteristic->setCallbacks(new charStatusCallbacks());
    characteristic->setValue("Sample value"); // Initial value for testing

    service->start();

    NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
    advertising->setName(DEVICE_NAME);
    advertising->addServiceUUID(SERVICE_UUID);
    advertising->enableScanResponse(true);
    if (!advertising->start()) return 4; // Advertising start error
    Serial.printf("[%s] BLE setup completed!\n", TAG);
    return 0;
}

void pushMessage(const char* message) {
    if (server->getConnectedCount() > 0) {
        characteristic->setValue(message);
        characteristic->notify(); // Notify all connected clients
        Serial.printf("[%s] Sent notify: %s\n", TAG, message);
    } else {
        Serial.printf("[%s] No clients connected. Message not sent: %s\n", TAG, message);
    }
}