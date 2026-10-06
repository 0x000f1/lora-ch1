import 'dart:async';
import 'dart:convert';
import 'package:app/db_service.dart';
import 'package:app/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// control characteristic for commands
BluetoothCharacteristic? _controlChar;

// data characteristic for messages
BluetoothCharacteristic? _dataChar;

// all incoming messages/commands will be stored in the 2 private broadcast streams
final _controlStreamController = StreamController<String>.broadcast();
final _dataStreamController = StreamController<String>.broadcast();

// public streams
Stream<String> get controlStream => _controlStreamController.stream;
Stream<String> get dataStream => _dataStreamController.stream;

// global subscriptions to handle canceling them later
StreamSubscription? _dataBleSub;
StreamSubscription? _controlBleSub;

// set up reading "listener"
Future<void> setupBleCommunication(BluetoothCharacteristic control, BluetoothCharacteristic data) async {
  _dataChar = data;
  _controlChar = control;

  // "subscribe" to characteristics
  await _dataChar!.setNotifyValue(true);
  await _controlChar!.setNotifyValue(true);

  // stop previous listeners to prevent duplicates when a device reconnects multiple times
  await _dataBleSub?.cancel();
  await _controlBleSub?.cancel();

  // store any incoming messages in the ble stream
  _dataBleSub = _dataChar!.lastValueStream.listen((value) async {
    if (value.isNotEmpty) {
      final rawMsg = utf8.decode(value);
      
      if (rawMsg.startsWith("ACK_OK") || rawMsg.startsWith("ERR_TIMEOUT")) {
        _dataStreamController.add(rawMsg);
        return;
      }
      
      final assambled = handleIncomingFragments(rawMsg);
      if (assambled != null) {
        _dataStreamController.add(assambled);
        _saveIncomingMessageToDb(assambled);
      }
    }
  });

  _controlBleSub = _controlChar!.lastValueStream.listen((value) {
    if (value.isNotEmpty) {
      String rawMsg = utf8.decode(value);

      if (rawMsg.startsWith("BAT;")) {
        final parts = rawMsg.split(";");
        if (parts.length >= 2) {
          batteryLevel.value = int.tryParse(rawMsg.split(";")[1]) ?? batteryLevel.value;
        }
      }
      _controlStreamController.add(rawMsg);
    }
  });
}

List<BluetoothCharacteristic> _foundChars = [];
List<BluetoothCharacteristic> get chars => _foundChars;
final ValueNotifier<bool> isDeviceConnected = ValueNotifier(false);

final ValueNotifier<int> unreadPrivateCount = ValueNotifier(0);
final ValueNotifier<int> unreadBroadcastCount = ValueNotifier(0);
final ValueNotifier<int> unreadUpdateTrigger = ValueNotifier(0);

final ValueNotifier<int> batteryLevel = ValueNotifier(0);
Timer? _batteryTimer;

Future<void> refreshUnreadCount() async {
  unreadPrivateCount.value = await getTotalUnreadPrivateCount();
  unreadBroadcastCount.value = await getUnreadBroadcastCount();
  unreadUpdateTrigger.value++;
}

Future<bool> _setDeviceTime() async {
  final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final String command = "SET_TIM;$currentTime";
  bool success = await sendCommandWithResponse(command, "TIM_OK");
  if (success) {
    AppLogger.log("[BLE]", "Set time successfully to $currentTime");
    return true;
  } else {
    AppLogger.log("[BLE]", "All set time attempts timed out.");
    return false;
  }
}

// global variable for storing vibration status
final ValueNotifier<bool> vibrationSetting = ValueNotifier(true);

// enable/disable vibration with SET_VIB
Future<bool> setVibration(bool isEnabled) async {
  final String command = "SET_VIB;${isEnabled ? 1 : 0}";
  bool success = await sendCommandWithResponse(command, "VIB_OK");
  if (success) {
    AppLogger.log("SETT", "Vibration setting ${isEnabled ? "enabled" : "disabled"}");
    return true;
  } else {
    AppLogger.log("SETT", "Failed to set vibration");
    return false;
  }
}

// GET_VIB; response = VIB;{0/1} 0 = haptic off, 1 = haptic on
Future<bool?> getVibration() async {
  String? response = await sendCommandAndFetch("GET_VIB", "VIB");

  if (response != null) {
    final parts = response.split(';');
    if (parts.length >= 2) {
      return parts[1] == '1';
    }
  }
  return null;
}

final ValueNotifier<String> usernameSetting = ValueNotifier("");

Future<bool> setUsername(String newName) async {
  if (newName.trim().isEmpty) return false;
  final String command = "SET_USR;$newName";
  bool success = await sendCommandWithResponse(command, "USR_OK");
  if (success) {
    usernameSetting.value = newName;
    AppLogger.log("SETT", "Username updated to: $newName");
    return true;
  } else {
    AppLogger.log("SETT", "Username failed to update");
    return false;
  }
}

Future<String?> getUsername() async {
  String? response = await sendCommandAndFetch("GET_USR", "USR");
  if (response != null) {
    final parts = response.split(";");
    if (parts.length >= 2) {
      return parts[1];
    }
  }
  return null;
}

// device color stored in hex
final ValueNotifier<String> colorSetting = ValueNotifier("");

Future<bool> setColor(String color) async {
  if (color.trim().isEmpty) return false;
  final String command = "SET_COL;$color";
  bool success = await sendCommandWithResponse(command, "COL_OK");
  if (success) {
    colorSetting.value = color;
    AppLogger.log("SETT", "Color updated to: $color");
    return true;
  } else {
    AppLogger.log("SETT", "Color failed to update");
    return false;
  }
}

Future<String?> getColor() async {
  String? response = await sendCommandAndFetch("GET_COL", "COL");
  if (response != null) {
    final parts = response.split(";");
    if (parts.length >= 2) {
      return parts[1];
    }
  }
  return null;
}

void _startBatteryUpdates() {
  _batteryTimer?.cancel();
  _batteryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    sendOnControlChar("GET_BAT");
  });
}

void initConnectionListener() {
  FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
    bool connected = event.connectionState == BluetoothConnectionState.connected;
    isDeviceConnected.value = connected;
    AppLogger.log("BLE", "Device connected state changed: ${isDeviceConnected.value}");

    if (connected) {
      _startBatteryUpdates();
    } else {
      _batteryTimer?.cancel();
      batteryLevel.value = 0;
    }
  });
}

// initialize/get settings after connecting
Future<void> _initializeDeviceSettings() async {
  await _setDeviceTime();

  bool? initialVib = await getVibration();
  if (initialVib != null) {
    vibrationSetting.value = initialVib;
  }

  String? initialUser = await getUsername();
  if (initialUser != null) {
    usernameSetting.value = initialUser;
  }

  String? initialColor = await getColor();
  if (initialColor != null) {
    colorSetting.value = initialColor;
  }
}

Future<bool> connectAndSetupDevice(BluetoothDevice device) async {
  _foundChars.clear();
  try {
    await device.connect();
    List<BluetoothService> services = await device.discoverServices();

    for (var service in services) {
      for (var char in service.characteristics) {
        if (char.properties.write && char.properties.notify) {
          _foundChars.add(char);
        }
      }
    }

    if (_foundChars.length == 2) {
      await setupBleCommunication(_foundChars[1], _foundChars[0]);
      await _initializeDeviceSettings();
      AppLogger.log("BLE", "Device connected and channels set up");
      return true;
    }
    AppLogger.log("BLE", "Failed to find characteristics");
    return false;
  } catch (e) {
    AppLogger.log("BLE", "Connection error: $e");
    return false;
  }
}

Future<void> disconnectDevice(BluetoothDevice device) async {
  await device.disconnect();
  _foundChars.clear();
}

// writing: returns true if message went throught, false otherwise
Future<bool> sendOnDataChar(String msg) async {
  // check if the device is connected to avoid errors
  if (_dataChar == null || !isDeviceConnected.value) return false;
  try {
    await _dataChar!.write(utf8.encode(msg));
    AppLogger.log("BLE", "Sent on Data char: $msg");
    return true;
  } catch (e) {
    AppLogger.log("BLE", "Error writing to control char: Message: $msg, Error: $e");
    return false;
  }
}

Future<bool> sendOnControlChar(String msg) async {
  if (_controlChar == null || !isDeviceConnected.value) return false;
  try {
    await _controlChar!.write(utf8.encode(msg));
    AppLogger.log("BLE", "Sent on Control char: $msg");
    return true;
  } catch (e) {
    AppLogger.log("BLE", "Error writing to data char: Message: $msg, Error: $e");
    return false;
  }
}

// split message into 240 byte sized fragments
List<String> splitMessage(String text) {
  final List<String> fragments = [];
  final StringBuffer currentFragment = StringBuffer();
  int currentFragmentBytes = 0;

  // in each iteration, check if current character can fit into a fragment without splitting a multi-byte character
  for (final char in text.characters) {
    final charBytes = utf8.encode(char).length;

    // reset current fragment if adding a character results in one over 240 bytes
    if (currentFragmentBytes + charBytes > 240) {
      fragments.add(currentFragment.toString());
      currentFragment.clear();
      currentFragmentBytes = 0;
    }
    // append character and update bytecount
    currentFragment.write(char);
    currentFragmentBytes += charBytes;
  }

  // add remaining text into a seperate fragment
  if (currentFragment.isNotEmpty) {
    fragments.add(currentFragment.toString());
  }

  return fragments;
}

// returns true if a message got an ack_ok response, false otherwise
Future<bool> _sendFragmentWithAck(String packet, String targetMac, int payloadBytes) async {
  // 3,5 seconds + 50ms/byte maximum timeout
  final timeout = Duration(milliseconds: 3500 + (payloadBytes * 50));

  // start stream before sending data
  final ackFuture = dataStream
      .firstWhere(
        (msg) => msg.startsWith("ACK_OK;$targetMac") || msg.startsWith("ERR_TIMEOUT;$targetMac"),
      )
      .timeout(timeout);

  await sendOnDataChar(packet);

  try {
    final response = await ackFuture;
    return response.startsWith("ACK_OK");
  } catch (e) {
    return false;
  }
}


Future<bool> sendMessage(String targetMac, String msg) async {
  final fragments = splitMessage(msg);
  final isBroadcast = targetMac == 'FFFFFFFF';

  for (int i = 0; i < fragments.length; i++) {
    final payload = fragments[i];
    final packet = "$targetMac;${i + 1};${fragments.length};$payload";

    AppLogger.log("BLE", "Sending fragment ${i + 1}/${fragments.length} ($payload)");

    if (isBroadcast) {
      // no ACK on broadcast
      await sendOnDataChar(packet);
      continue;
    }
    
    // send every packet with a seperate ACK check
    final payloadBytes = utf8.encode(payload).length;
    final ackReceived = await _sendFragmentWithAck(packet, targetMac, payloadBytes);
    if (ackReceived) AppLogger.log("BLE", "ACK recieved for fragment ${i+1}/${fragments.length}");

    if (!ackReceived) {
      AppLogger.log("BLE", "Message failed to send: $msg");
      await updateLastMessageStatus(targetMac, 'failed');
      return false;
    }
    
  }

  if (!isBroadcast) {
    await updateLastMessageStatus(targetMac, 'delivered');
  }

  AppLogger.log("CHAT", "Sent message: $msg");
  return true;
}

Future<bool> sendBroadcastMsg(String msg) async {
  bool success = await sendMessage("FFFFFFFF", msg);
  AppLogger.log("CHAT", "Sent broadcast message $msg");
  return success;
}

Future<bool> sendPrivateMsg(String targetMac, String msg) async {
  bool success = await sendMessage(targetMac, msg);
  AppLogger.log("CHAT", "Sent private message $msg to $targetMac");
  return success;
}

final Map<String, String> _incomingBuffers = {};
String? handleIncomingFragments(String rawData) {
  final parts = rawData.split(';');
  if (parts.length < 9) return rawData;

  final senderMac = parts[0];
  final senderUsername = parts[1];
  final colorHex = parts[2];
  final targetMac = parts[3];
  final currentFragment = int.tryParse(parts[4]);
  final totalFragments = int.tryParse(parts[5]);
  final timeStamp = parts[6];
  final rssi = parts[7];
  final payload = parts.sublist(8).join(';');

  if (currentFragment == null || totalFragments == null || totalFragments <= 1) {
    return "$senderMac;$senderUsername;$colorHex;$targetMac;$timeStamp;$rssi;$payload";
  }

  AppLogger.log("BLE", "Fragment $currentFragment/$totalFragments from $senderMac");

  if (currentFragment == 1) {
    // on first fragment, override/create entry
    _incomingBuffers[senderMac] = payload;
  } else {
    // append other fragments
    _incomingBuffers[senderMac] = (_incomingBuffers[senderMac] ?? '') + payload;
  }

  if (currentFragment == totalFragments) {
    final completeMessage = _incomingBuffers.remove(senderMac) ?? payload;
    AppLogger.log("CHAT", "Complete message recieved from $senderMac");
    // returned with fragment info removed
    return "$senderMac;$senderUsername;$colorHex;$targetMac;$timeStamp;$rssi;$completeMessage";
  }

  return null;
}

Future<void> _saveIncomingMessageToDb(String rawMsg) async {
  final parts = rawMsg.split(';');
  if (parts.length >= 7) {
    final senderMac = parts[0];
    final senderUser = parts[1];
    final targetMac = parts[3];
    final timeStamp = int.tryParse(parts[4]) ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final payload = parts.sublist(6).join(';');
    final isBroadcast = targetMac == 'FFFFFFFF';

    final message = DbMessage(
      peerMac: isBroadcast ? null : senderMac,
      senderName: senderUser,
      content: payload,
      isMe: false,
      timestamp: timeStamp,
      isBroadcast: isBroadcast,
    );
    await InsertMessage(message);
  }
}

// send a SET command on control stream that has an expected response (SET_TIM: TIM_OK) etc..
Future<bool> sendCommandWithResponse(String command, String expectedReponse) async {
  for (int i = 0; i <= 3; i++) {
    try {
      final response = controlStream.firstWhere((msg) => msg == expectedReponse).timeout(Duration(seconds: 3));

      bool sent = await sendOnControlChar(command);
      if (!sent) return false;

      await response;
      return true;
    } catch (e) {
      if (i == 3) {
        return false;
      }
    }
  }
  return false;
}

// send a GET request on command stream to get a stored value
Future<String?> sendCommandAndFetch(String command, String expectedPrefix) async {
  for (int i = 0; i <= 3; i++) {
    try {
      final responseFuture = controlStream
          .firstWhere((msg) => msg.startsWith(expectedPrefix))
          .timeout(const Duration(seconds: 3));

      bool sent = await sendOnControlChar(command);
      if (!sent) return null;

      return await responseFuture;
    } catch (e) {
      if (i == 3) return null;
    }
  }
  return null;
}
