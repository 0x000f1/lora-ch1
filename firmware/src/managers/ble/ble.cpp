#include "ble.h"
#include "managers/system/system_manager.h"
#include "utils/log_helper.h"
#include <NimBLEDevice.h>
#include "managers/lora/lora.h"
#include "managers/ble/ble.h"
#include "drivers/ui/haptic.h"
#include <esp_bt.h>
#include <sys/time.h>

#define TAG "BLE" 

// String -> Float converter
// The FreeRTOS crash handle, avoids atof() 
float parseToFloat(const char* s) {
    float res = 0.0f;
    float fact = 1.0f;
    bool point_seen = false;
    int sign = 1;

    if (*s == '-') {
        sign = -1;
        s++;
    }

    for (int i = 0; s[i]; i++) {
        if (s[i] == '.') {
            point_seen = true;
            continue;
        }
        if (s[i] >= '0' && s[i] <= '9') {
            int d = s[i] - '0';
            if (point_seen) {
                fact /= 10.0f;
                res = res + d * fact;
            } else {
                res = res * 10.0f + d;
            }
        }
    }
    return res * sign;
}

static NimBLEServer* server = nullptr;
static NimBLECharacteristic* dataCharacteristic = nullptr;
static NimBLECharacteristic* controlCharacteristic = nullptr;

TimerHandle_t BLEManager::pairingTimer = nullptr;
volatile bool BLEManager::shutdownPending = false;
static bool isRadioSleeping = false; // Track the state of the radio
volatile bool BLEManager::pushStoredPending = false;
char BLEManager::messageBuffer[MAX_STORED_MESSAGES][300];
uint8_t BLEManager::messageCount = 0;

bool BLEManager::isBLEActive() {
    return NimBLEDevice::isInitialized() && 
        (NimBLEDevice::getAdvertising()->isAdvertising() || 
        (server != nullptr && server->getConnectedCount() > 0));
}

bool BLEManager::isConnected() {
    return server != nullptr && server->getConnectedCount() > 0;
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

    if (pushStoredPending) {
        pushStoredPending = false;
        pushStoredMessages();
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
            // Stack Overflow fix: Store on Heap
            DiscoveryInfo* list = new DiscoveryInfo[MAX_NEIGHBORS];
            uint8_t count = 0;

            if (!LoRaManager::getNeighbors(list, MAX_NEIGHBORS, count)) {
                nimBleChar->setValue("NEI_ERR");
                nimBleChar->notify();
                delete[] list;
                return;
            }

            if (count == 0) {
                LOG_I(TAG, "No neighbors found.");
                nimBleChar->setValue("NEI|NO_NEI");
            } else {
                std::string response = "NEI|";
                for (uint8_t i = 0; i < count; i++) {
                    char responseBuffer[150];

                    // Remove the %f (mutex crash)
                    int latInt = (int)list[i].latitude;
                    int latFrac = (int)(abs(list[i].latitude - latInt) * 1000000);
                    int lonInt = (int)list[i].longitude;
                    int lonFrac = (int)(abs(list[i].longitude - lonInt) * 1000000);
                    int rssiInt = (int)list[i].rssi;
                    int rssiFrac = (int)(abs(list[i].rssi - rssiInt) * 100);

                    snprintf(responseBuffer, sizeof(responseBuffer), 
                                            "%08X;%s;%02X%02X%02X;%d.%02d;%lu;%d.%06d;%d.%06d|",
                                            list[i].senderAddress, 
                                            list[i].senderUsername,
                                            list[i].colorR,
                                            list[i].colorG,
                                            list[i].colorB,
                                            rssiInt, rssiFrac, // %.2f
                                            list[i].timestamp,
                                            latInt, latFrac, // %.6f
                                            lonInt, lonFrac); // %.6f
                    response += responseBuffer;
                }
                nimBleChar->setValue(response);
            }
            nimBleChar->notify();
            delete[] list;
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
        else if (strncmp(cmd, "SET_TIM;", 8) == 0) {
            const char* payloadStr = cmd + 8;
            
            struct timeval timeValue;
            timeValue.tv_sec = strtol(payloadStr, NULL, 10); // Convert string to UNIX timestamp
            timeValue.tv_usec = 0;
            
            settimeofday(&timeValue, NULL); // ESP32 internal system time set
            
            nimBleChar->setValue("TIM_OK");
            nimBleChar->notify();
            LOG_I(TAG, "Time synced via BLE to UNIX epoch: %ld", timeValue.tv_sec);
        }
        else if (strcmp(cmd, "GET_ID") == 0) {
            uint32_t localAddress = SystemManager::getLoRaID();
            char response[64];
            snprintf(response, sizeof(response), "ID;%08X", localAddress);
            
            nimBleChar->setValue(std::string(response));
            nimBleChar->notify();
            LOG_I(TAG, "Sent local address to client: %08X", localAddress);
        }
        else if (strcmp(cmd, "GET_VIB") == 0) {
            uint32_t hapticsStatus = SystemManager::getHapticsProfile();
            char response[10];
            snprintf(response, sizeof(response), "VIB;%d", hapticsStatus);
            
            nimBleChar->setValue(std::string(response));
            nimBleChar->notify();
            LOG_I(TAG, "Sent haptics status to client: %d", hapticsStatus);
        }
        else if (strncmp(cmd, "SET_VIB;", 8) == 0) {
            const char* payloadStr = cmd + 8;

            int32_t payloadValue = atoi(payloadStr);
            SystemManager::setHapticsProfile(payloadValue);
            
            nimBleChar->setValue("VIB_OK");
            nimBleChar->notify();
            LOG_I(TAG, "Haptics status updated: %d", (uint8_t)payloadValue);
        }
        else if (strcmp(cmd, "RST") == 0) {
            LOG_I(TAG, "Command received: RST. Restarting.");
            nimBleChar->setValue("RST_OK");
            if (!nimBleChar->notify()) {
                LOG_W(TAG, "Failed to notify RST_OK.");
            }

            // Do not block the NimBLE host task while waiting for the notification.
            BaseType_t taskCreated = xTaskCreate([](void* pvParameters) {
                vTaskDelay(pdMS_TO_TICKS(1000));
                SystemManager::reboot();
                vTaskDelete(NULL);
            }, "RebootTask", 2048, NULL, 1, NULL);

            if (taskCreated != pdPASS) {
                LOG_E(TAG, "Failed to create delayed reboot task.");
                SystemManager::reboot();
            }
        }
        else if (strcmp(cmd, "FACTORY_RESET") == 0) {
            LOG_W(TAG, "Command received: FACTORY_RESET. Erasing NVS then restart.");
            nimBleChar->setValue("FACTORY_RESET_OK");
            nimBleChar->notify();
            vTaskDelay(pdMS_TO_TICKS(100));
            SystemManager::factoryReset();
        }
        else if (strcmp(cmd, "FIND") == 0) {
            LOG_I(TAG, "Command received: FIND. Starting 5s haptics.");
            nimBleChar->setValue("FIND_OK");
            nimBleChar->notify();

            // Async FreeRTOS thread (non blocking) for 5 sec
            xTaskCreate([](void* pvParameters) {
                unsigned long startTime = millis();
                
                // for 5 sec (5 000 ms) replay the 15 (750 ms Alert 100%) effect
                while (millis() - startTime < 5000) {
                    HapticManager::playEffect(15);
                    
                    // Wait 1 sec (750 ms playtime, 250 ms free time)
                    vTaskDelay(pdMS_TO_TICKS(1000)); 
                }
                
                LOG_I("BLE", "FIND haptics finished.");
                vTaskDelete(NULL); // Delete the FreeRTOS thread
            }, "PingTask", 2048, NULL, 1, NULL);
        }
        else if (strncmp(cmd, "SET_LOC;", 8) == 0) {
            // Format: SET_LOC;47.5316;21.6273
            // If location not enabled (NO_LOC): SET_LOC;0.0;0.0
            const char* payloadStr = cmd + 8;
            
            char locBuffer[50];
            strncpy(locBuffer, payloadStr, sizeof(locBuffer) - 1);
            locBuffer[sizeof(locBuffer) - 1] = '\0';

            char* separator = strchr(locBuffer, ';');
            if (separator != nullptr) {
                *separator = '\0';
                float lat = parseToFloat(locBuffer);
                float lon = parseToFloat(separator + 1);
                
                SystemManager::setLocation(lat, lon);
                
                // Remove the %f (mutex crash)
                int latInt = (int)lat;
                int latFrac = (int)(abs(lat - latInt) * 1000000);
                int lonInt = (int)lon;
                int lonFrac = (int)(abs(lon - lonInt) * 1000000);

                LOG_I(TAG, "Location updated via BLE: Lat: %d.%06d, Lon: %d.%06d", latInt, latFrac, lonInt, lonFrac);
                nimBleChar->setValue("LOC_OK");
            } else {
                LOG_W(TAG, "Invalid location format received.");
                nimBleChar->setValue("LOC_ERR");
            }
            nimBleChar->notify();
        }
        else if (strcmp(cmd, "GET_LOC") == 0) {
            float lat, lon;
            SystemManager::getLocation(lat, lon);
            
            int latInt = (int)lat;
            int latFrac = (int)(abs(lat - latInt) * 1000000);
            int lonInt = (int)lon;
            int lonFrac = (int)(abs(lon - lonInt) * 1000000);

            char response[64];
            // Remove the %f (mutex crash)
            snprintf(response, sizeof(response), "LOC;%d.%06d;%d.%06d", latInt, latFrac, lonInt, lonFrac);
            
            nimBleChar->setValue(std::string(response));
            nimBleChar->notify();
            LOG_I(TAG, "Sent current location to client: %d.%06d, %d.%06d", latInt, latFrac, lonInt, lonFrac);
        }
        else if (strcmp(cmd, "NO_LOC") == 0) {
            SystemManager::setLocation(0.0f, 0.0f);
            
            nimBleChar->setValue("NO_LOC_OK");
            nimBleChar->notify();
            LOG_I(TAG, "Location sharing disabled via BLE (coordinates set to 0.0).");
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

    void onSubscribe(NimBLECharacteristic* characteristic, NimBLEConnInfo& connInfo, uint16_t subValue) override {
        LOG_I(TAG, "DATA subscription changed: 0x%04X", subValue);

        if (subValue != 0 && BLEManager::messageCount > 0) {
            BLEManager::pushStoredPending = true;
        }
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

void BLEManager::storeMessage(const char* message) {
    if (messageCount < MAX_STORED_MESSAGES) {
        strncpy(messageBuffer[messageCount], message, sizeof(messageBuffer[0]) - 1);
        messageBuffer[messageCount][sizeof(messageBuffer[0]) - 1] = '\0';
        messageCount++;
        LOG_I(TAG, "Message stored in buffer. Total stored: %d", messageCount);
    } else {
        LOG_W(TAG, "Message buffer full! Dropping oldest message.");
        // Ring buffer: push the whole buffer left, the oldest buffer will be 'removed' from the list.
        for(int i = 0; i < MAX_STORED_MESSAGES - 1; i++) {
            strncpy(messageBuffer[i], messageBuffer[i+1], sizeof(messageBuffer[0]));
        }
        strncpy(messageBuffer[MAX_STORED_MESSAGES - 1], message, sizeof(messageBuffer[0]) - 1);
    }
}

void BLEManager::pushStoredMessages() {
    if (messageCount == 0 || server == nullptr || server->getConnectedCount() == 0) {
        return;
    }

    LOG_I(TAG, "Pushing %d stored messages to client...", messageCount);

    uint8_t i = 0;
    while (i < messageCount) {
        dataCharacteristic->setValue(std::string(messageBuffer[i]));
        bool success = dataCharacteristic->notify();

        if (!success) {
            LOG_W(TAG, "BLE notify failed");
            return;
        }

        LOG_I(TAG, "Pushed stored message: %s", messageBuffer[i]);

        for (uint8_t j = i; j < messageCount - 1; ++j) {
            strncpy(messageBuffer[j], messageBuffer[j + 1], sizeof(messageBuffer[j]) - 1);
            messageBuffer[j][sizeof(messageBuffer[j]) - 1] = '\0';
        }
        messageCount--;

        vTaskDelay(pdMS_TO_TICKS(50)); // 50 ms break for BLE stability
    }
}

void BLEManager::pushMessage(const char* message, bool isBroadcast) {
    if (server != nullptr && dataCharacteristic != nullptr && server->getConnectedCount() > 0) {
        dataCharacteristic->setValue(std::string(message));
        dataCharacteristic->notify(); // Notify all connected clients
        LOG_I(TAG, "Sent notify: %s", message);
    } else if (!isBroadcast) {
        // Save only if: NO connected client + NOT broadcast message received
        LOG_W(TAG, "No clients connected. Saving direct message to the buffer.");
        storeMessage(message);
    } else {
        LOG_I(TAG, "Broadcast message ignored for storage.");
    }
}