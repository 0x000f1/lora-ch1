import 'package:flutter/material.dart';

// color as hex string without alpha, e.g. "FF9800"
String colorToHex(Color color) {
  return color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
}

// prevents ui crash by validating hex string
Color? hexToColor(String hex) {
  // check for 6 valid hex characters
  if(RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    return Color(int.parse('FF$hex', radix: 16));
  }
  
  // return null on invalid hex
  return null;
}