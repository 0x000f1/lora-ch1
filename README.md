
# lora-ch1

This project is based on the ESP32-C3 microcontroller that behaves like a bridge between mobile devices and the modules. The connection is established via Bluetooth Low Energy with the phone, then sends the package over the LoRa (RFM98W) module at 433 MHz. This combination is able to perform a full internet-independent communication between two or more devices, at a long range.

## Functions

* **Bidirectional communication:** Transmit packages seamlessly between two or more devices (P2P or Broadcast).
* **Neighbour Discovery:** Automatic heartbeat messages are sent out to advertise the active device among other users, storing the RSSI and last active timestamp.
* **Dynamic NVS management:** The device name, UUIDs, and unique identifiers are generated on the first startup and stored in the NVS.
* **Energy management:** Currently, it supports 3 different power profiles that change the frequency of the CPU and the heartbeat interval. 

---

##  BLE API Documentation

The mobile app connects to the ESP32 and manages the LoRa module (and some settings).

### 1. Discovering the device (Scanning & Connection)

* **Device Name:** The ESP32 starts advertising in this format `lora-ch1-XXXX` where the `XXXX` is the device's MAC address's last 2 bytes (e.g., `lora-ch1-A1B2`).
* **Dynamic UUIDs:** **IMPORTANT!** On the first start, the device generates (Version 4) UUIDs for the services and characteristics. The mobile device should use **Service Discovery** instead of hardcoded UUIDs!

### 2. Services and characteristics

The system advertises a single main Service, under which two characteristics (Data and Control) are located. Both characteristics support `READ`, `WRITE`, and `NOTIFY` operations. 

#### A. Data Characteristic
Actual message sending and receiving takes place on this channel.

* **Sending (App -> LoRa):**
  * Write a String to this characteristic.
  * The ESP32 immediately puts this onto the LoRa network (currently as a Broadcast message to all nearby nodes).
  * *Limitation:* The maximum message length is currently about 240-245 bytes due to LoRa payload limits.
* **Receiving (LoRa -> App):**
  * The app must subscribe to `NOTIFY` events on this characteristic.
  * If the ESP32 receives data from another LoRa node (a `PKG_DATA` type package), it sends it out to the BLE client as a String via a Notify event.

#### B. Control Characteristic
This channel is used to query the network status.

* **Commands (App -> ESP32):**
  * `GET_NEI`: Queries the currently known LoRa network neighbors.
* **Responses (ESP32 -> App):**
  * The app must subscribe to `NOTIFY` events.
  * Once the command is executed, the ESP32 sends one of the following responses via Notify:
    * `NO_NEI`: If there are currently no known neighbors in range.
    * `MAC,RSSI;MAC,RSSI;`: If there are neighbors, it sends the MAC addresses (HEX) and the last known RSSI (signal strength) values separated by semicolons (e.g., `A1B2C3D4,-45.50;F1E2D3C4,-80.00;`).

---

## Future Developments (TODO)

The project is under active development. The planned features in order:

1. **Fragmentation:** Automatic splitting and reassembly of BLE messages larger than 250 bytes on the LoRa side.
2. **Direct P2P communication:** Targeted message sending instead of Broadcast.
3. **ACK mechanism:** Automatic retry in case of failed package transmission.
4. **BLE Security:** "Just Works" or Passkey-based pairing for secure access.
5. **LoRa Encryption:** Payload encryption (AES).
6. **Deep/Light Sleep:** Placing the ESP32 and LoRa module into sleep mode depending on the Power Profiles.

---
*Built using the RadioLib and NimBLE-Arduino libraries.*
