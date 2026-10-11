// BLE data transmission (raw read and write on characteristics)

import 'dart:async';
import 'dart:convert';

import 'package:app/core/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';


// control characteristic for commands
BluetoothCharacteristic? _controlChar;

// data characteristic for messages
BluetoothCharacteristic? _dataChar;

// raw packets of data char: ACK, key fragments, messages
final _rawDataStreamController = StreamController<String>.broadcast();

// raw packets of control char: getters, ACK packets (VIB_OK,USR_OK,etc)
final _controlStreamController = StreamController<String>.broadcast();

// public streams
Stream<String> get controlStream => _controlStreamController.stream;
Stream<String> get rawDataStream => _rawDataStreamController.stream;

// global subscriptions to handle canceling them later
StreamSubscription? _dataBleSub;
StreamSubscription? _controlBleSub;

final ValueNotifier<bool> isDeviceConnected = ValueNotifier(false);

// set up reading "listener"
Future<void> setupBleCommunication(
  BluetoothDevice device,
  BluetoothCharacteristic control,
  BluetoothCharacteristic data,
) async {
  _dataChar = data;
  _controlChar = control;

  // stop previous listeners to prevent duplicates when a device reconnects multiple times
  await _dataBleSub?.cancel();
  await _controlBleSub?.cancel();

  // only handles decoding incoming values to utf8
  _dataBleSub = _dataChar!.onValueReceived.listen((value) {
    if(value.isEmpty) return;
    _rawDataStreamController.add(utf8.decode(value));
  });
  device.cancelWhenDisconnected(_dataBleSub!);

  _controlBleSub = _controlChar!.onValueReceived.listen((value) {
    if (value.isEmpty) return;
    String rawMsg = utf8.decode(value);
    _controlStreamController.add(rawMsg);
  });

  device.cancelWhenDisconnected(_controlBleSub!);

  // "subscribe" to characteristics
  await _dataChar!.setNotifyValue(true);
  await _controlChar!.setNotifyValue(true);
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
    AppLogger.log("BLE", "Error writing to data char: Message: $msg, Error: $e");
    return false;
  }
}

Future<bool> sendOnControlChar(String msg) async {
  if (_controlChar == null) {
    AppLogger.log("BLE", "Cannot send $msg: control characteristic is null");
    return false;
  }
  if (!isDeviceConnected.value) {
    AppLogger.log("BLE", "Cannot send $msg: device is disconnected");
    return false;
  }
  try {
    await _controlChar!.write(utf8.encode(msg));
    AppLogger.log("BLE", "Sent on Control char: $msg");
    return true;
  } catch (e) {
    AppLogger.log("BLE", "Error writing to control char: Message: $msg, Error: $e");
    return false;
  }
}

// send a SET command on control stream that has an expected response (SET_TIM: TIM_OK) etc..
Future<bool> sendCommandWithResponse(String command, String expectedReponse) async {
  for (int i = 0; i <= 3; i++) {
    try {
      final response = controlStream.firstWhere((msg) => msg == expectedReponse).timeout(Duration(seconds: 3));

      // if command is RST it drops the BLE connection immediately
      bool sent = await sendOnControlChar(command).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          AppLogger.log("BLE", "Timed out writing control command: $command");
          return false;
        },
      );
      if (!sent) {
        // ignore reponse future to avoid timeout
        response.ignore();
        return false;
      }

      final String responseString = await response;
      AppLogger.log("BLE", "Recieved reponse: $responseString for command $command");
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
      final response = controlStream
          .firstWhere((msg) => msg.startsWith(expectedPrefix))
          .timeout(const Duration(seconds: 3));

      bool sent = await sendOnControlChar(command);
      if (!sent) {
        response.ignore();
        return null;
      }

      return await response;
    } catch (e) {
      if (i == 3) return null;
    }
  }
  return null;
}