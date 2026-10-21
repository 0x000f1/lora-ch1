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

// queue command to prevent overlapping responses
Future<void> _controlLock = Future.value();

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
    if (value.isEmpty) return;
    // prevents crashes on split multi-byte characters
    // needed for older bluetooth versions
    String rawMsg = utf8.decode(value, allowMalformed: true);
    _rawDataStreamController.add(rawMsg);
  });
  device.cancelWhenDisconnected(_dataBleSub!);

  _controlBleSub = _controlChar!.onValueReceived.listen((value) {
    if (value.isEmpty) return;
    String rawMsg = utf8.decode(value, allowMalformed: true);
    _controlStreamController.add(rawMsg);
  });

  device.cancelWhenDisconnected(_controlBleSub!);

  // "subscribe" to characteristics
  await _dataChar!.setNotifyValue(true);
  await _controlChar!.setNotifyValue(true);
}

// write to data/control characteristic
Future<bool> _writeToCharacteristics(BluetoothCharacteristic? char, String msg, String charName) async {
  if(char == null || isDeviceConnected.value) return false;
  
  try {
    await char.write(utf8.encode(msg));
    AppLogger.log("BLE", "Sent on $charName char: $msg");
    return true;
  } catch (e) {
    AppLogger.log("BLE", "Error writing to $charName char: Message: $msg, Error: $e");
    return false;
  }
}

// writing: returns true if message went throught, false otherwise
Future<bool> sendOnDataChar(String msg) async {
  return await _writeToCharacteristics(_dataChar, msg, "Data");
}

Future<bool> sendOnControlChar(String msg) async {
  return await _writeToCharacteristics(_controlChar, msg, "Control");
}

// queue commands and wait for specified response
Future<String?> _enqueueCommand(String command, String expectedResponse) {
  final completer = Completer<String?>();

  // command to the end of the queue
  _controlLock = _controlLock.whenComplete(() async {
    try {
      // setup listener for expected response before sending
      final responseFuture = controlStream
          .firstWhere((msg) => msg == expectedResponse || msg.startsWith("$expectedResponse;"))
          .timeout(const Duration(seconds: 3), onTimeout: () => "TIMEOUT");
          
      bool sent = await sendOnControlChar(command);
      if(!sent) {
        responseFuture.ignore();
        return completer.complete(null);
      }
      
      completer.complete(await responseFuture);
    } catch (e) {
      completer.complete(null);
    }
  });
  
  return completer.future;
}

// send a SET command on control stream that has an expected response (SET_TIM: TIM_OK, etc) and factory reset/restart
Future<bool> sendCommandWithResponse(String command, String expectedReponse) async {
  final response = await _enqueueCommand(command, expectedReponse);
  
  if (response == "TIMEOUT") {
    // handle special case for factory reset and restart in case the connection drops before response
    if (command == "RST" || command == "FACTORY_RESET") {
      AppLogger.log("BLE", "Device restarted before sending $expectedReponse, assuming success");
      return true;
    }
    return false;
  }
  
  if(response == null) return false;
  
  AppLogger.log("BLE", "Recieved response: $response for command $command");
  return true;
}

// send a GET request on command stream to get a stored value
Future<String?> sendCommandAndFetch(String command, String expectedPrefix) async {
  final response = await _enqueueCommand(command, expectedPrefix);
  
  if (response == "TIMEOUT" || response == null) return null;
  
  return response;
}
