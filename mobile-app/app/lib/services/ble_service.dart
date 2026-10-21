// BLE connection management and entry file for services

import 'dart:async';
import 'package:app/services/neighbor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:app/core/logger.dart';
import 'package:app/services/device_commands.dart';
import 'package:app/services/message_fragmenter.dart';
import 'package:app/services/ble_transport.dart';
import 'package:app/services/messaging_service.dart';

export 'package:app/services/device_commands.dart';
export 'package:app/services/encryption_service.dart';
export 'package:app/services/message_fragmenter.dart';
export 'package:app/services/ble_transport.dart';
export 'package:app/services/messaging_service.dart';

// stores discovered data and control characteristics
List<BluetoothCharacteristic> _foundChars = [];
List<BluetoothCharacteristic> get chars => _foundChars;

// global varible for bluetooth state
final ValueNotifier<bool> isBluetoothOn = ValueNotifier(false);

// prevent duplicate event subscriptions
bool _isListenerInitialized = false;

// tracks currently active device to ignore events from disconnected device
BluetoothDevice? _activeDevice;

// set up global listeners
void initConnectionListener() {
  if (_isListenerInitialized) return;
  _isListenerInitialized = true;
  
  startMessageProcessing();
  
  // tracks if the phone's bluetooth is on or off
  FlutterBluePlus.adapterState.listen((state) {
    isBluetoothOn.value = state == BluetoothAdapterState.on;
    AppLogger.log("BLE", "Bluetooth adapter state: ${state.name}");
  });
  
  
  FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
    // ignore events from previously connected devices, or disconnecting ones
    if (_activeDevice != null && event.device.remoteId != _activeDevice!.remoteId) return;
    
    bool connected = event.connectionState == BluetoothConnectionState.connected;
    isDeviceConnected.value = connected;
    AppLogger.log("BLE", "Device connected state changed: ${isDeviceConnected.value}");

    if (connected) {
      startBatteryUpdates();
    } else {
      clearFragmentBuffers();
      stopBatteryUpdates();
      stopNeighborProcessing();
    }
  });
}

// connects to a device, discovers services and prepapres BLE channels
Future<bool> connectAndSetupDevice(BluetoothDevice device) async {
  _foundChars.clear();
  
  // disconnect previous device when trying to connect to a new one
  for (var connectedDevice in FlutterBluePlus.connectedDevices) {
    if(connectedDevice.remoteId != device.remoteId) {
      await connectedDevice.disconnect();
    }
  }
  
  // mark the device
  _activeDevice = device;
  
  try {
    await device.connect();
    List<BluetoothService> services = await device.discoverServices();

    for (var service in services) {
      for (var char in service.characteristics) {
        // filter for characteristics that support write and notify
        if (char.properties.write && char.properties.notify) {
          _foundChars.add(char);
        }
      }
    }

    if (_foundChars.length == 2) {
      // index 1 is control, index 0 is data on hardware
      await setupBleCommunication(device, _foundChars[1], _foundChars[0]);
      await initializeDeviceSettings();
      AppLogger.log("BLE", "Device connected and channels set up");
      return true;
    }
    AppLogger.log("BLE", "Failed to find characteristics");
    // disconnect on channel setup fail
    await device.disconnect();
    return false;
  } catch (e) {
    AppLogger.log("BLE", "Connection error: $e");
    await device.disconnect();
    return false;
  }
}

// disconnect device and reset state
Future<void> disconnectDevice(BluetoothDevice device) async {
  await device.disconnect();
  
  if (_activeDevice?.remoteId == device.remoteId) {
    _activeDevice = null;
  }
  
  _foundChars.clear();
  clearFragmentBuffers();
}


StreamSubscription<List<ScanResult>>? _scanSub;

// scans for nearby lora devices, merge them with connected device for UI
Future<void> startBluetoothDeviceScan(Function(List<BluetoothDevice>) onDevicesUpdated) async {
  _scanSub?.cancel();
  
  // keep connected device in list
  final connected = FlutterBluePlus.connectedDevices.where(
    (d) => d.platformName.startsWith("lora-ch1"),
  );
  
  // show connected device on UI
  onDevicesUpdated(connected.toList());
  
  try {
    // fine location needed on android for scanning
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 30), androidUsesFineLocation: true);

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final scanned = results
          .map((r) => r.device)
          .where((d) => d.platformName.startsWith('lora-ch1'));

      final combined = {...connected, ...scanned}.toList();
      
      onDevicesUpdated(combined);
    });
  } catch (e) {
    AppLogger.log("BLE", "Failed to start scan");
  }
}

// cancel ongoing scan
void stopBluetoothScan() {
  _scanSub?.cancel();
  FlutterBluePlus.stopScan();
}
