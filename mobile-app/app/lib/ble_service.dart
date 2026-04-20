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
Future<void> setupBleCommunication(BluetoothCharacteristic control, BluetoothCharacteristic data) async {
  _dataChar = data;
  _controlChar = control;

  // "subscribe" to characteristics
  await _dataChar!.setNotifyValue(true);
  await _controlChar!.setNotifyValue(true);


  // store any incoming messages in the ble stream
  _dataChar!.lastValueStream.listen((value) {
    if(value.isNotEmpty) {
      _dataStreamController.add(utf8.decode(value));
    }
  });

  _controlChar!.lastValueStream.listen((value) {
    if(value.isNotEmpty) {
      _controlStreamController.add(utf8.decode(value));
    }
  });
}

// writing
Future<void> sendOnDataChar(String msg) async => await _dataChar?.write(utf8.encode(msg));
Future<void> sendOnControlChar(String msg) async => await _dataChar?.write(utf8.encode(msg));

Future<void> sendBroadcastMsg(String msg) async {
  final formattedMsg = "FFFFFFFF;1;1;$msg";
  await _dataChar?.write(utf8.encode(formattedMsg));
}