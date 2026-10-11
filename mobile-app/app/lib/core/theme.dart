import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  splashFactory: NoSplash.splashFactory, // default ios/android animations off

  textTheme: GoogleFonts.spaceGroteskTextTheme(
    ThemeData.dark().textTheme,
  ).apply(bodyColor: Colors.white60, displayColor: Colors.white60),

  colorScheme: ColorScheme.dark(
    primary: Colors.lightBlue.shade300,
    onPrimary: Colors.black,

    secondary: Colors.blue.shade300,
    onSecondary: Colors.black,

    surface: Colors.grey.shade900,
    onSurface: Colors.white,

    // elevated surface colors for layered widgets
    surfaceContainer: const Color(0xFF303030), // grey.shade850
    surfaceContainerHighest: Colors.grey.shade800,

    // primary-colored surfaces and the content color displayed on them
    primaryContainer: Colors.blue.shade900,
    onPrimaryContainer: Colors.grey.shade300,

    // secondary-colored surfaces and the content color displayed on them
    secondaryContainer: Colors.cyan.shade900,
    onSecondaryContainer: Colors.cyan.shade100,
  ),
  scaffoldBackgroundColor: Colors.grey.shade900,

  appBarTheme: AppBarThemeData(
    backgroundColor: Colors.grey.shade900,
    foregroundColor: Colors.white,
    elevation: 0,
  ),

  listTileTheme: ListTileThemeData(
    textColor: Colors.white,
    iconColor: Colors.lightBlue.shade300,
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.grey.shade900,
    labelStyle: TextStyle(color: Colors.grey.shade400),
    hintStyle: TextStyle(color: Colors.grey.shade500),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade700),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.lightBlue.shade300, width: 2),
    ),
  ),

  dividerTheme: DividerThemeData(color: Colors.grey.shade700),

  iconTheme: IconThemeData(color: Colors.blueGrey.shade500),
);

BoxDecoration msgDecoration(BuildContext context, bool isMe) {
  return BoxDecoration(
    color: isMe ? Colors.blueGrey.shade800 : Colors.grey.shade700,
    borderRadius: BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      // logic for rouding only "outer" edges resulting in the text bubble look
      bottomLeft: Radius.circular(isMe ? 16 : 0),
      bottomRight: Radius.circular(isMe ? 0 : 16),
    ),
  );
}
