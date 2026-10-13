// BLE connection management and entry file for services

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:app/core/logger.dart';
import 'package:app/services/location_service.dart';
import 'package:app/services/device_commands.dart';
import 'package:app/services/message_fragmenter.dart';
import 'package:app/services/ble_transport.dart';
import 'package:app/services/messaging_service.dart';

export 'package:app/services/location_service.dart';
export 'package:app/services/device_commands.dart';
export 'package:app/services/encryption_service.dart';
export 'package:app/services/message_fragmenter.dart';
export 'package:app/services/ble_transport.dart';
export 'package:app/services/messaging_service.dart';


List<BluetoothCharacteristic> _foundChars = [];
List<BluetoothCharacteristic> get chars => _foundChars;


void initConnectionListener() {
  startMessageProcessing();
  FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
    bool connected = event.connectionState == BluetoothConnectionState.connected;
    isDeviceConnected.value = connected;
    AppLogger.log("BLE", "Device connected state changed: ${isDeviceConnected.value}");

    if (connected) {
      startBatteryUpdates();
      // startLocationUpdates();
    } else {
      clearFragmentBuffers();
      // stopLocationUpdates();
      stopBatteryUpdates();
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
      await setupBleCommunication(device, _foundChars[1], _foundChars[0]);
      await initializeDeviceSettings();
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
  clearFragmentBuffers();
}