import 'package:flutter/material.dart';

class AppTheme {
  static const Color _bg = Color(0xFF050510);
  static const Color _cyan = Color(0xFF00F3FF);

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: _bg,
      primaryColor: _cyan,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: _cyan,
        secondary: _cyan,
        surface: _bg,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'monospace',
        bodyColor: _cyan,
        displayColor: _cyan,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        foregroundColor: _cyan,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.zero),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _cyan, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _cyan, width: 1.5),
        ),
        labelStyle: TextStyle(color: _cyan),
        hintStyle: TextStyle(color: Color(0xAA00F3FF)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _bg,
          foregroundColor: _cyan,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          side: const BorderSide(color: _cyan, width: 1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _cyan,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          side: const BorderSide(color: _cyan, width: 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _cyan,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _bg,
        foregroundColor: _cyan,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      dividerColor: const Color(0x6600F3FF),
    );
  }
}

