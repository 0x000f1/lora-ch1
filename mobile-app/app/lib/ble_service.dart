import 'dart:async';
import 'dart:convert';
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
Future<void> setupBleCommunication(
  BluetoothCharacteristic control,
  BluetoothCharacteristic data,
) async {
  _dataChar = data;
  _controlChar = control;

  // "subscribe" to characteristics
  await _dataChar!.setNotifyValue(true);
  await _controlChar!.setNotifyValue(true);

  // stop previous listeners to prevent duplicates when a device reconnects multiple times
  await _dataBleSub?.cancel();
  await _controlBleSub?.cancel();

  // store any incoming messages in the ble stream
  _dataBleSub = _dataChar!.lastValueStream.listen((value) {
    if (value.isNotEmpty) {
      _dataStreamController.add(utf8.decode(value));
    }
  });

  _controlBleSub = _controlChar!.lastValueStream.listen((value) {
    if (value.isNotEmpty) {
      String rawMsg = utf8.decode(value);

      if (rawMsg.startsWith("BAT;")) {
        final parts = rawMsg.split(";");
        if (parts.length >= 2) {
          batteryLevel.value =
              int.tryParse(rawMsg.split(";")[1]) ?? batteryLevel.value;
        }
      }
      _controlStreamController.add(rawMsg);
    }
  });
}

List<BluetoothCharacteristic> _foundChars = [];
List<BluetoothCharacteristic> get chars => _foundChars;
final ValueNotifier<bool> isDeviceConnected = ValueNotifier(false);
final ValueNotifier<int> batteryLevel = ValueNotifier(0);
Timer? _batteryTimer;

Future<void> _setDeviceTime() async {
  final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final String command = "SET_TIM;$currentTime";
  bool success = await sendCommandWithResponse(command, "TIM_OK");
  if(success) {
    AppLogger.log("[BLE]", "Set time successfully to $currentTime");
  }
  else {
    AppLogger.log("[BLE]", "All set time attempts timed out.");
  }
}

void _startBatteryUpdates() {
  _batteryTimer?.cancel();
  _batteryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    sendOnControlChar("GET_BAT");
  });
}

void initConnectionListener() {
  FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
    bool connected =
        event.connectionState == BluetoothConnectionState.connected;
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
      AppLogger.log("BLE", "Device connected and channels set up");
      await _setDeviceTime();
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

Future<void> sendBroadcastMsg(String msg) async {
  final formattedMsg = "FFFFFFFF;1;1;$msg";
  await sendOnDataChar(formattedMsg);
  AppLogger.log("CHAT", "Sent broadcast message: $msg");
}

Future<void> sendPrivateMsg(String targetMac, String msg) async {
  final formattedMsg = "$targetMac;1;1;$msg";
  await sendOnDataChar(formattedMsg);
  AppLogger.log("CHAT", "Sent private message: $msg");
}

// send a command on control stream that has an expected response (SET_TIM: TIM_OK) etc..
Future<bool> sendCommandWithResponse(String command, String expectedReponse) async {
  for (int i = 0; i <= 3; i++) {
    try {
      final response = controlStream
          .firstWhere((msg) => msg == expectedReponse)
          .timeout(Duration(seconds: 3));

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
