import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// https://docs.flutter.dev/cookbook/design/themes

final appTheme = ThemeData(
  splashFactory: NoSplash.splashFactory, // default ios/android animations off
  scaffoldBackgroundColor: Colors.white,
  colorScheme: ColorScheme.dark(
    primary: Colors.lightBlue.shade200,
    secondary: Colors.lightBlueAccent,
  ),
  appBarTheme: AppBarThemeData(
    backgroundColor: Colors.lightBlue.shade300,
    foregroundColor: Colors.black,
  ),
  iconTheme: IconThemeData(color: Colors.black),
);
