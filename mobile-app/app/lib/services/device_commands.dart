// device configuration and getters (battery, username, color, haptics, etc)

import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:app/services/ble_service.dart';
import 'package:app/core/constants.dart';
import 'package:app/core/logger.dart';
import 'package:flutter/material.dart';



// initialize/get settings after connecting
Future<void> initializeDeviceSettings() async {
  await _setDeviceTime();
  await _updateBatteryStatus();
  
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
  
  String? deviceId = await getDeviceId();
  if (deviceId != null) {
    myDeviceId.value = deviceId;
  }
}

Future<bool> _setDeviceTime() async {
  final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final String command = "SET_TIM;$currentTime";
  bool success = await sendCommandWithResponse(command, "TIM_OK");
  if (success) {
    AppLogger.log("BLE", "Set time successfully to $currentTime");
    return true;
  } else {
    AppLogger.log("BLE", "All set time attempts timed out.");
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

Future<bool> factoryResetDevice() async {
  bool success = await sendCommandWithResponse("FACTORY_RESET", "FACTORY_RESET_OK");
  if (success) {
    AppLogger.log("SETT", "Factory reset command sent successfully");
    return true;
  } else {
    AppLogger.log("SETT", "Failed to send factory reset command");
    return false;
  }
}

Future<bool> restartDevice() async {
  bool success = await sendCommandWithResponse("RST", "RST_OK");
  if (success) {
    AppLogger.log("SETT", "Device restart command sent successfully");
    return true;
  } else {
    AppLogger.log("SETT", "Failed to send device restart command");
    return false;
  }
}

final ValueNotifier<String> usernameSetting = ValueNotifier("");
// valid username: letters, numbers + space, ., -, _
final _validUserNameRegex = RegExp(r'^[\p{L}0-9_\-\. ]+$', unicode: true);

Future<bool> setUsername(String newName) async {
  final trimmed = newName.trim();
  if (trimmed.isEmpty) return false;

  if (!_validUserNameRegex.hasMatch(trimmed)) {
    AppLogger.log("SETT", "Username contains invalid characters: $trimmed");
    return false;
  }

  if (trimmed.length > maxUserNameLength) {
    AppLogger.log("SETT", "Username exceeds $maxUserNameLength limit: $trimmed");
    return false;
  }

  final String command = "SET_USR;$trimmed";
  bool success = await sendCommandWithResponse(command, "USR_OK");
  if (success) {
    usernameSetting.value = trimmed;
    AppLogger.log("SETT", "Username updated to: $trimmed");
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

final ValueNotifier<int> batteryLevel = ValueNotifier(0);
Timer? _batteryTimer;

Future<void> _updateBatteryStatus() async {
  String? response = await sendCommandAndFetch("GET_BAT", "BAT");
  // use old value if request fails
  if (response == null) return;

  final parts = response.split(';');
  if (parts.length < 3) return;

  final val = parts[1];
  final charging = parts[2];
  
  // device cant send battery level while charging
  // if battery is charging, then treat it as 110% and dont display value on UI
  if(charging == '1'){
    batteryLevel.value = batteryChargingValue;
    return;
  }
  
  batteryLevel.value = int.tryParse(val) ?? batteryLevel.value;
}

void startBatteryUpdates() {
  _batteryTimer?.cancel();
  _batteryTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
    await _updateBatteryStatus();
  });
}

void stopBatteryUpdates() {
  _batteryTimer?.cancel();
  _batteryTimer = null;
  batteryLevel.value = 0;
}

final ValueNotifier<String?> myDeviceId = ValueNotifier(null);

Future<String?> getDeviceId() async {
  String? response = await sendCommandAndFetch("GET_ID", "ID");
  AppLogger.log("BLE", "Recieved response for GET_ID: $response");
  if (response == null) return null;
  final parts = response.split(';');
  if(parts.length < 2) return null;
  return parts[1];
}