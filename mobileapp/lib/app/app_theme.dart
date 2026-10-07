import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color backgroundDark = Color(0xFF090A0F);
  static const Color cardDark = Color(0xFF12141D);
  static const Color cardBorder = Color(0xFF1F2433);
  static const Color neonGreen = Color(0xFF30D158);
  static const Color neonBlue = Color(0xFF0A84FF);
  static const Color neonOrange = Color(0xFFFF9F0A);
  static const Color neonRed = Color(0xFFFF453A);
  static const Color neonPurple = Color(0xFFBF5AF2);

  static ThemeData getDarkTheme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: backgroundDark,
    cardColor: cardDark,
    dividerColor: cardBorder,
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    colorScheme: const ColorScheme.dark(
      primary: neonGreen,
      surface: backgroundDark,
    ),
  );

  static ThemeData getLightTheme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    cardColor: const Color(0xFFFFFFFF),
    dividerColor: const Color(0xFFE2E8F0),
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
    colorScheme: const ColorScheme.light(
      primary: neonGreen,
      surface: Color(0xFFF8FAFC),
    ),
  );
}
