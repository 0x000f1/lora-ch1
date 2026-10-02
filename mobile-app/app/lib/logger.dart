import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';


class AppLogger {
  static void log(String category, String message) {
    if (kDebugMode) {
      final formattedTime = DateTime.now().toString().substring(11,19);
      debugPrint("[LOGGER][$category][$formattedTime] -> $message");
    }
  }
}