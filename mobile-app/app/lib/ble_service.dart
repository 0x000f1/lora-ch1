import 'dart:async';
import 'dart:convert';
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

  // store any incoming messages in the ble stream
  _dataChar!.lastValueStream.listen((value) {
    if (value.isNotEmpty) {
      _dataStreamController.add(utf8.decode(value));
    }
  });

  _controlChar!.lastValueStream.listen((value) {
    if (value.isNotEmpty) {
      String rawMsg = utf8.decode(value);

      if (rawMsg.startsWith("BAT;")) {
        batteryLevel.value =
            int.tryParse(rawMsg.split(";")[1]) ?? batteryLevel.value;
      }
      _controlStreamController.add(utf8.decode(value));
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
  debugPrint("Current time= $currentTime");
  // try 3 times before timing out
  for (int i = 0; i <= 3; i++) {
    try {
      // stream listener first to not miss replies
      final response = controlStream
          .firstWhere((msg) => msg == "TIM_OK")
          .timeout(const Duration(seconds: 2));
      
      sendOnControlChar("SET_TIM;$currentTime");
      // wait for response
      await response;

      debugPrint("Set time successful");
      return;
    } catch (e) {
      debugPrint("[$i] Set time attempt timed out");
      if (i == 3) {
        debugPrint("All set time attempts timed out.");
      }
    }
  }
}

void _startBatteryUpdates() {
  _batteryTimer?.cancel();
  _batteryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    sendOnControlChar("GET_BAT");
  });
}

void initConnectionListener() {
  FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
    bool connected =
        event.connectionState == BluetoothConnectionState.connected;
    isDeviceConnected.value = connected;
    debugPrint("Device connected? ${isDeviceConnected.value}");
    debugPrint("Battery level: ${batteryLevel.value}");

    if (connected) {
      _startBatteryUpdates();
      _setDeviceTime();
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
      return true;
    }
    return false;
  } catch (e) {
    return false;
  }
}

Future<void> disconnectDevice(BluetoothDevice device) async {
  await device.disconnect();
  _foundChars.clear();
}

// writing
Future<void> sendOnDataChar(String msg) async {
  // check if the device is connected to avoid errors
  if (_dataChar == null || !isDeviceConnected.value) return;
  try {
    await _dataChar!.write(utf8.encode(msg));
  } catch (e) {
    print(e);
  }
}

Future<void> sendOnControlChar(String msg) async {
  if (_controlChar == null || !isDeviceConnected.value) return;
  try {
    await _controlChar!.write(utf8.encode(msg));
  } catch (e) {
    debugPrint(e.toString());
  }
}

Future<void> sendBroadcastMsg(String msg) async {
  final formattedMsg = "FFFFFFFF;1;1;$msg";
  await _dataChar?.write(utf8.encode(formattedMsg));
  debugPrint("Sent message $formattedMsg");
}

Future<void> sendPrivateMsg(String targetMac, String msg) async {
  final formattedMsg = "$targetMac;1;1;$msg";
  await sendOnDataChar(formattedMsg);
}
