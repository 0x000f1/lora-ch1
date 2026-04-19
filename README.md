# lora-ch1

This project is based on the ESP32-C3 microcontroller that behaves like a bridge between mobile devices and the modules. The connection is established via Bluetooth Low Energy with the phone, then sends the package over the LoRa (RFM98W/SX1278) module at 433 MHz. This combination is able to perform a full internet-independent communication between two or more devices, at a long range.

## Functions

* **Reliable Bidirectional Communication:** Transmit packages seamlessly between two or more devices. Supports public Broadcasts and private P2P messages with an Automatic Repeat Request (ARQ) mechanism. P2P messages are automatically acknowledged (ACK) and retried up to 3 times if lost in the air.
* **Fast TX & Continuous RX Architecture:** Optimized for ultra-low latency and high reliability. By utilizing a minimal preamble (12 symbols), the Time on Air (ToA) is reduced to ~90ms, virtually eliminating packet collisions while ensuring zero message drops through continuous background listening. *Thread-safe implementation prevents conflicts between BLE and LoRa tasks.*
* **Smart Neighbour Discovery:** Automatic heartbeat messages are sent out to advertise the active device among other users, storing the RSSI and last active timestamp. The system automatically cleans up "dead" or out-of-range nodes after 120 seconds of inactivity.
* **Haptic & UI Feedback:** Integrated DRV2605L haptic motor driver and hardware button with debouncing. Provides distinct physical feedback for button presses and incoming LoRa messages, with strict power-management (zero idle consumption).
* **BLE Security (Just Works):** Implements physical button-press validation to activate BLE advertising (Pairing Mode) for 60 seconds, preventing unauthorized external connections.
* **Dynamic NVS Management:** The device name, UUIDs, unique LoRa ID, and user preferences (Username, UI Color) are generated on the first startup and safely stored in the Non-Volatile Storage (NVS).
* **Duty Cycle Monitoring:** Tracks and logs the Time on Air (ToA) and calculates the current duty cycle percentage to assist with regulatory compliance (e.g., the 10% limit on 433MHz in Europe).
* **Energy Management:** Supports 3 different power profiles (`BATTERY_SAVER`, `BALANCED`, `PERFORMANCE`) that dynamically scale the CPU frequency and adjust the heartbeat intervals.

## BLE API Documentation

The mobile app connects to the ESP32 and manages the LoRa module (and some settings).

### 1. Discovering the device (Scanning & Connection)

* **IMPORTANT (MTU Size):** The Android application **MUST** request an MTU size of 512 bytes (`requestMtu(512)`) immediately after the connection is established. Without this, Android will truncate incoming messages to 20 bytes! iOS handles this automatically.
* **Device Name:** The ESP32 starts advertising in this format `lora-ch1-XXXX` where the `XXXX` is the device's MAC address's last 2 bytes (e.g., `lora-ch1-A1B2`).
* **Dynamic UUIDs:** **IMPORTANT!** On the first start, the device generates (Version 4) UUIDs for the services and characteristics. The mobile device should use **Service Discovery** instead of hardcoded UUIDs!
* **Pairing Mode:** The device is hidden by default. Press the physical button on the device to enable Bluetooth visibility for 60 seconds.

### 2. Services and characteristics

The system advertises a single main Service, under which two characteristics (Data and Control) are located. Both characteristics support `READ`, `WRITE`, and `NOTIFY` operations.

#### A. Data Characteristic
Actual message sending and receiving takes place on this channel. The payload must follow a semicolon-separated format to support message fragmentation and direct addressing.

* **Sending (App -> LoRa):**
  * **Format:** `TARGET_MAC;CURRENT_FRAGMENT;TOTAL_FRAGMENTS;PAYLOAD`
  * Write a String to this characteristic using the format above.
  * *Target MAC:* 8-character HEX string. Use `FFFFFFFF` to Broadcast to everyone, or a specific device's LoRa ID for a private P2P message.
  * *Example (Broadcast):* `FFFFFFFF;1;1;Hello everyone!`
  * *Example (P2P Fragmented):* `ABCD1234;1;3;This is a long me`
  * *Limitation:* The `PAYLOAD` length per BLE write should be kept around 240 bytes due to LoRa airtime limitations.

* **Receiving (LoRa -> App):**
  * The app must subscribe to `NOTIFY` events on this characteristic.
  * **Format 1 (Standard Data):** `SENDER_MAC;TARGET_MAC;CURRENT_FRAGMENT;TOTAL_FRAGMENTS;PAYLOAD`
    * The app can use the `TARGET_MAC` to determine if the received message was a public broadcast (`FFFFFFFF`) or a private P2P message meant specifically for this user.
  * **Format 2 (Delivery Success):** `ACK_OK;TARGET_MAC`
    * Sent to the app when a previously sent P2P message is successfully acknowledged by the receiver.
  * **Format 3 (Delivery Failed):** `ERR_TIMEOUT;TARGET_MAC`
    * Sent to the app when a P2P message fails to reach the target after maximum retries or channel collisions.

#### B. Control Characteristic
This channel is used to query the network status and manage system preferences.

* **Commands (App -> ESP32) & Responses (via NOTIFY):**
  * `GET_NEI`
    * *Response:* `MAC;RSSI;TIMESTAMP|MAC,RSSI;TIMESTAMP|` (e.g., `A1B2C3D4;-45.50;32125|...`) or `NO_NEI` if the list is empty.
  * `GET_BAT`
    * *Response:* `BAT;87` (Returns the battery percentage 0-100).
  * `SET_USR;Username`
    * *Action:* Saves the string to NVS (max length depends on BLE MTU, trims whitespaces).
    * *Response:* `USR_OK`
  * `GET_USR`
    * *Response:* `USR;Username` (Defaults to `Guest` if not set).
  * `SET_COL;HexColor`
    * *Action:* Saves the UI color HEX string to NVS (e.g., `FF0000`).
    * *Response:* `COL_OK`
  * `GET_COL`
    * *Response:* `COL;HexColor` (Defaults to `0088FF` if not set).
  * `SET_PWR;ProfileName`
    * *Action:* Sets the active power profile (`BATTERY_SAVER`, `BALANCED`, `PERFORMANCE`).
    * *Response:* `PWR_OK` or `PWR_ERR` (if the profile name is invalid).

## Future Developments (TODO)

The project is under active development. The planned features in order:

1. **Hardware ADC Integration:** Implement real battery voltage reading via the ESP32's ADC pins to replace the simulated `GET_BAT` response.
2. **Advanced Power Management:** Optimizing ESP32 Light Sleep modes to reduce the idle current consumption (~40mA) without disrupting the Continuous LoRa RX and BLE states.
3. **LoRa Encryption:** Payload encryption (AES-128/256) to secure over-the-air data against eavesdropping.

---
*Built using the RadioLib and NimBLE-Arduino libraries.*
