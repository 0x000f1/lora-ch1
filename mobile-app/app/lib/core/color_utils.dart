import 'package:flutter/material.dart';

// color as hex string without alpha, e.g. "FF9800"
String colorToHex(Color color) {
  return color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
}

// inverse of colorToHex, the color is always fully opaque
Color hexToColor(String hex) {
  return Color(int.parse('FF$hex', radix: 16));
}