# lora-ch1

This project is based on the ESP32-C3 microcontroller that behaves like a bridge between mobile devices and the modules. The connection is established via Bluetooth Low Energy with the phone, then sends the package over the LoRa (RFM98W/SX1278) module at 433 MHz. This combination is able to perform a full internet-independent communication between two or more devices, at a long range.

## Hardware Specification & Pinout

The current hardware is based on the ESP32-C3 microcontroller, interfaced with an RFM98W/SX1278 LoRa module, a DRV2605L haptic driver, and a BQ24075 based charging circuit.

`![PCB Layout](docs/lora_ch1.png)`

### ESP32-C3 GPIO Mapping

| Component | Pin Name | ESP32-C3 GPIO | Description |
| :--- | :--- | :--- | :--- |
| **LoRa (SPI)** | MISO | GPIO 5 | Master In Slave Out |
| | MOSI | GPIO 6 | Master Out Slave In |
| | NSS | GPIO 7 | Chip Select (CS) |
| | SCK | GPIO 4 | SPI Clock |
| | DIO1 | GPIO 3 | IRQ / Interrupt 1 |
| | DIO0 | GPIO 10 | IRQ / Interrupt 0 |
| | RST | GPIO 2 | LoRa Reset |
| **I2C Bus** | SDA | GPIO 8 | I2C Data (DRV2605L) |
| | SCL | GPIO 9 | I2C Clock (DRV2605L) |
| **Haptic Driver** | DRV_EN | GPIO 21 | Enable pin for DRV2605L |
| **Power / Battery** | CHRG | GPIO 20 | Charging status (BQ24075, LOW = charging) |
| | BAT_SENS | GPIO 1 | Battery Voltage ADC (ADC_11db attenuation) |
| **User Input** | BUTTON | GPIO 0 | Hardware Button (with debouncing) |

### Development Environment & Flashing
* **IDE:** **PlatformIO**
* **Board:** **`esp32-c3-devkitm-1`**

## Functions

* **Reliable Bidirectional Communication:** Transmit packages seamlessly between two or more devices. Supports public Broadcasts and private P2P messages with an Automatic Repeat Request (ARQ) mechanism. P2P messages are automatically acknowledged (ACK) and retried up to 3 times if lost in the air.
* **Fast TX & Continuous RX Architecture:** Optimized for ultra-low latency and high reliability in the prototype phase. By utilizing an optimized preamble (12 symbols), the Time on Air (ToA) is reduced to ~100-132ms (payload dependent), virtually eliminating packet collisions while ensuring zero message drops through continuous background listening. *Thread-safe FreeRTOS implementation prevents conflicts between BLE and LoRa tasks*.
* **Offline Message Buffer:** Safely stores up to 32 incoming direct (P2P) messages in the RAM if the phone is disconnected. Upon BLE reconnection, all buffered messages are instantly pushed to the app. Public Broadcasts are ignored for offline storage to preserve memory.
* **Smart Neighbour Discovery:** Automatic heartbeat messages are sent out to advertise the active device among other users, storing the RSSI, last active timestamp, and the user's custom RGB UI color. The system automatically cleans up "dead" or out-of-range nodes after a timeout period based on the active power profile.
* **Haptic & UI Feedback:** Integrated DRV2605L haptic motor driver and hardware button with debouncing. Provides distinct physical feedback for button presses, incoming LoRa messages, and an automatic low battery warning (triggered below 15% while discharging).
* **BLE Security (Just Works):** Implements physical button-press validation to activate BLE advertising (Pairing Mode) for 60 seconds, preventing unauthorized external connections.
* **Dynamic NVS Management:** The device name, UUIDs, unique LoRa ID, haptic profile, and user preferences (Username, UI Color) are generated on the first startup and safely stored in the Non-Volatile Storage (NVS).
* **Duty Cycle Monitoring:** Tracks and logs the Time on Air (ToA) and calculates the current duty cycle percentage to assist with regulatory compliance (e.g., the 10% limit on 433MHz in Europe).
* **Automated Power Management:** Supports 3 different power profiles (`BATTERY_SAVER`, `BALANCED`, `PERFORMANCE`) that dynamically scale the CPU frequency (80MHz or 160MHz) and adjust heartbeat intervals (10 min, 5 min, and 1 min respectively). The device defaults to `BATTERY_SAVER` on boot. Pressing the hardware button temporarily wakes the system into `BALANCED` mode for BLE communication.
* **Real Battery Monitoring:** Built-in hardware ADC integration calculates real battery percentage, and monitors the active charging status via the BQ24075 charging IC's open-drain output (GPIO 20).

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
  * **Format 1 (Standard Data):** `SENDER_MAC;TARGET_MAC;CURRENT_FRAGMENT;TOTAL_FRAGMENTS;TIMESTAMP;RSSI;PAYLOAD`
    * The app can use the `TARGET_MAC` to determine if the received message was a public broadcast (`FFFFFFFF`) or a private P2P message.
    * Sender username sent from the device NVS.
    * `TIMESTAMP`: The UNIX Epoch time in seconds. If the device clock is not synced via `SET_TIM`, this value returns `0`.
    * `RSSI`: The signal strength of the received LoRa package (e.g., `-78.00`).
  * **Format 2 (Delivery Success):** `ACK_OK;TARGET_MAC`
    * Sent to the app when a previously sent P2P message is successfully acknowledged by the receiver.
  * **Format 3 (Delivery Failed):** `ERR_TIMEOUT;TARGET_MAC`
    * Sent to the app when a P2P message fails to reach the target after maximum retries or channel collisions.

#### B. Control Characteristic
This channel is used to query the network status and manage system preferences.

* **Commands (App -> ESP32) & Responses (via NOTIFY):**
  * `SET_TIM;UnixSeconds`
    * *Action:* Syncs the ESP32's internal RTC to the real-world UNIX epoch time (e.g., `SET_TIM;1715423000`). Must be sent immediately after connecting.
    * *Response:* `TIM_OK`
  * `GET_NEI`
    * *Response:* `NEI|MAC;NEI_USERNAME;COLOR_HEX;RSSI;TIMESTAMP|MAC;NEI_USERNAME;COLOR_HEX;RSSI;TIMESTAMP|` (e.g., `NEI|A1B2C3D4;lora-ch1-XXXX;FF0000;-45.50;32125|...`) or `NEI|NO_NEI` if the list is empty. Note: The `COLOR_HEX` is a 6-character string representing the neighbor's RGB preference.
  * `GET_BAT`
    * *Response:* `BAT;Percentage;IsCharging` (e.g., `BAT;87;1` where 1 means charging, 0 means discharging).
  * `SET_USR;Username`
    * *Action:* Saves the string to NVS. Cannot contain `;` or `|` characters, and trims whitespaces. Defaults to `Guest` if empty or invalid.
    * *Response:* `USR_OK`
  * `GET_USR`
    * *Response:* `USR;Username` (Defaults to `Guest` if not set).
  * `SET_COL;HexColor`
    * *Action:* Saves the UI color HEX string to NVS (e.g., `FF0000`). Reverts to `0088FF` if the format is invalid.
    * *Response:* `COL_OK`
  * `GET_COL`
    * *Response:* `COL;HexColor` (Defaults to `0088FF` if not set).
  * `SET_PWR;ProfileName`
    * *Action:* Sets the active power profile (`BATTERY_SAVER`, `BALANCED`, `PERFORMANCE`).
    * *Response:* `PWR_OK` or `PWR_ERR` (if the profile name is invalid).
  * `GET_VIB`
    * *Response:* `VIB;{0/1}` Where 0 means haptics is off, 1 means haptics is on.
  * `SET_VIB;STATUS`
    * *Action:* `1` turns on (by default) the haptic feedback actuator, `0` turns off.
    * *Response:* `VIB_OK` means the command ran.
  * `GET_ID`
    * *Response:* `ID;LOCAL_ID` (e.g., `ID;3FFE78C0`) returns the LoRa local address.
  * `RST`
    * *Action:* Restarts the ESP, needs to reconnect after!
    * *Response:* `RST_OK`
  * `FACTORY_RESET`
    * *Action:* Erases the whole NVS partition, clears color, username, and all settings. The ESP restarts automatically. The LoRa MAC and UUIDs will be regenerated on the next boot.
    * *Response:* `FACTORY_RESET_OK`