import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final appTheme = ThemeData(
  splashFactory: NoSplash.splashFactory, // default ios/android animations off
  textTheme: GoogleFonts.spaceGroteskTextTheme(),
  scaffoldBackgroundColor: Colors.white,
  colorScheme: ColorScheme.dark(
    primary: Colors.lightBlue.shade200,
    secondary: Colors.lightBlueAccent,
  ),
  appBarTheme: AppBarThemeData(
    backgroundColor: Colors.blue.shade300,
    foregroundColor: Colors.black,
  ),
  iconTheme: IconThemeData(color: Colors.lightBlue.shade300),
);

BoxDecoration msgDecoration(bool isMe){
  return BoxDecoration(
    color: isMe ? Colors.blue.shade800 : Colors.grey.shade300,
    borderRadius: BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      // logic for rouding only "outer" edges resulting in the text bubble look
      bottomLeft: Radius.circular(isMe ? 16 : 0),
      bottomRight: Radius.circular(isMe ? 0 : 16),
    )
  );
}
