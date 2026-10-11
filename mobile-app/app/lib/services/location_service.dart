// background location tracking and coordinate transmission

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';


import 'package:app/services/ble_service.dart';
import 'package:app/core/logger.dart';

Timer? _locationTimer;

// whether the phone's location is forwarded to device. if off, it will send 0;0
final ValueNotifier<bool> locationSetting = ValueNotifier(true);

Future<bool> _isPermissionsGranted() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    AppLogger.log("LOC", "Location services are disabled.");
    return false;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      AppLogger.log("LOC", "Location permissions are disabled.");
      return false;
    }
  }
  return true;
}

Future<bool> _sendCurrentLocation() async {
  // if user disabled location, send a 0;0 coordinate
  if(!locationSetting.value) {
    bool success = await sendCommandWithResponse("SET_LOC;0;0", "LOC_OK");
    if (success) {
      AppLogger.log("LOC", "Location cleared (0;0 sent)");
    }
    return success;
  }
  
  
  final bool permissionsGranted = await _isPermissionsGranted();
  if (!permissionsGranted) {
    return false;
  }

  try {
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    final String command = "SET_LOC;${position.latitude};${position.longitude}";

    bool success = await sendCommandWithResponse(command, "LOC_OK");
    if (success) {
      AppLogger.log("LOC", "Location sent successfully: ${position.latitude}, ${position.longitude}");
      return true;
    } else {
      AppLogger.log("LOC", "Failed to send location");
      return false;
    }
  } catch (e) {
    AppLogger.log("LOC", "Error getting location: $e");
    return false;
  }
}

Future<bool> setLocationSharing(bool isEnabled) async {
  locationSetting.value = isEnabled;
  return await _sendCurrentLocation();
}
 
Future<void> startLocationUpdates() async {
  final bool permissionsGranted = await _isPermissionsGranted();
  if (!permissionsGranted) return;

  _locationTimer?.cancel();
  _locationTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
    await _sendCurrentLocation();
  });
}

void stopLocationUpdates() {
  _locationTimer?.cancel();
  _locationTimer = null;
}