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
  static const Color successLight = Color(0xFF198754);
  static const Color informationLight = Color(0xFF0066CC);
  static const Color warningLight = Color(0xFFB45309);
  static const Color dangerLight = Color(0xFFC62828);
  static const _actionIconStyle = ButtonStyle(
    iconSize: WidgetStatePropertyAll(20),
  );

  static ThemeData getDarkTheme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    iconButtonTheme: const IconButtonThemeData(style: _actionIconStyle),
    elevatedButtonTheme: const ElevatedButtonThemeData(style: _actionIconStyle),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: _actionIconStyle),
    textButtonTheme: const TextButtonThemeData(style: _actionIconStyle),
    scaffoldBackgroundColor: backgroundDark,
    cardColor: cardDark,
    dividerColor: cardBorder,
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    colorScheme: const ColorScheme.dark(
      primary: neonGreen,
      surface: backgroundDark,
      error: neonRed,
    ),
  );

  static ThemeData getLightTheme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    iconButtonTheme: const IconButtonThemeData(style: _actionIconStyle),
    elevatedButtonTheme: const ElevatedButtonThemeData(style: _actionIconStyle),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: _actionIconStyle),
    textButtonTheme: const TextButtonThemeData(style: _actionIconStyle),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    cardColor: const Color(0xFFFFFFFF),
    dividerColor: const Color(0xFFE2E8F0),
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
    colorScheme: const ColorScheme.light(
      primary: neonGreen,
      surface: Color(0xFFF8FAFC),
      error: dangerLight,
    ),
  );
}
