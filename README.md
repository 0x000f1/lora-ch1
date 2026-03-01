# lora-ch1

This project is based on the ESP32-C3 microcontroller that behaves like a bridge between mobile devices and the modules. The connection is established via Bluetooth Low Energy with the phone, then sends the package over the LoRa (RFM98W) module at 433 MHz. This combination is able to perform a full internet-independent communication between two or more devices, at a long range.

## Functions

* **Bidirectional communication:** Transmit packages seamlessly between two or more devices (P2P or Broadcast).
* **Neighbour Discovery:** Automatic heartbeat messages are sent out to advertise the active device among other users, storing the RSSI and last active timestamp.
* **Dynamic NVS management:** The device name, UUIDs, and unique identifiers are generated on the first startup and stored in the NVS.
* **Energy management:** Currently, it supports 3 different power profiles that change the frequency of the CPU and the heartbeat interval.

---

## BLE API Documentation

The mobile app connects to the ESP32 and manages the LoRa module (and some settings).

### 1. Discovering the device (Scanning & Connection)

* **IMPORTANT (MTU Size):** The Android application **MUST** request an MTU size of 512 bytes (`requestMtu(512)`) immediately after the connection is established. Without this, Android will truncate incoming messages to 20 bytes! iOS handles this automatically.
* **Device Name:** The ESP32 starts advertising in this format `lora-ch1-XXXX` where the `XXXX` is the device's MAC address's last 2 bytes (e.g., `lora-ch1-A1B2`).
* **Dynamic UUIDs:** **IMPORTANT!** On the first start, the device generates (Version 4) UUIDs for the services and characteristics. The mobile device should use **Service Discovery** instead of hardcoded UUIDs!

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
  * **Format:** `SENDER_MAC;TARGET_MAC;CURRENT_FRAGMENT;TOTAL_FRAGMENTS;PAYLOAD`
  * The app can use the `TARGET_MAC` to determine if the received message was a public broadcast (`FFFFFFFF`) or a private P2P message meant specifically for this user.
  * *Example:* `9A8B7C6D;FFFFFFFF;1;1;Hi, I received it!`

#### B. Control Characteristic
This channel is used to query the network status.

* **Commands (App -> ESP32):**
  * `GET_NEI`: Queries the currently known LoRa network neighbors.
* **Responses (ESP32 -> App):**
  * The app must subscribe to `NOTIFY` events.
  * Once the command is executed, the ESP32 sends one of the following responses via Notify:
    * `NO_NEI`: If there are currently no known neighbors in range.
    * `MAC,RSSI;MAC,RSSI;TIMESTAMP`: If there are neighbors, it sends the MAC addresses (HEX), the last known RSSI (signal strength) and timestamp values separated by semicolons (e.g., `A1B2C3D4,-45.50;F1E2D3C4,-80.00;32125`).

---

## Future Developments (TODO)

The project is under active development. The planned features in order:

1. **Neighbor Cleanup (Anti-Zombie):** Automatically remove disconnected or out-of-range nodes from the neighbor list.
2. **ACK mechanism & Retries:** Automatic retry in case of a failed P2P package transmission.
3. **BLE Security:** "Just Works" or Passkey-based pairing for secure access.
4. **LoRa Encryption:** Payload encryption (AES-128/256) to secure over-the-air data.
5. **Deep/Light Sleep:** Placing the ESP32 and LoRa module into sleep mode depending on the Power Profiles.

---
*Built using the RadioLib and NimBLE-Arduino libraries.*