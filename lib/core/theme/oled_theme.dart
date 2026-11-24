import 'package:flutter/material.dart';

/// Design System Cyber-OLED Executive — SUTURA VAULT (Section 6).
class OledTheme {
  OledTheme._();

  static const Color bgPrimary = Color(0xFF0D0F12);
  static const Color surfaceDark = Color(0xFF13171F);
  static const Color surfaceCard = Color(0xFF1A1D24);
  static const Color borderSubtle = Color(0xFF222734);

  static const Color accentEmerald = Color(0xFF2ECC71);
  static const Color accentBlue = Color(0xFF3498DB);
  static const Color accentAmber = Color(0xFFF39C12);
  static const Color accentRed = Color(0xFFE74C3C);

  static const Color textPrimary = Color(0xFFF2F5F9);
  static const Color textSecondary = Color(0xFF94A0B8);
  static const Color textMuted = Color(0xFF636E82);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      colorScheme: const ColorScheme.dark(
        primary: accentEmerald,
        secondary: accentBlue,
        error: accentRed,
        surface: surfaceDark,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgPrimary,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentEmerald, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceCard,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: accentEmerald.withValues(alpha: 0.4)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentEmerald;
          return textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentEmerald.withValues(alpha: 0.25);
          }
          return surfaceDark;
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: borderSubtle,
        thickness: 1,
      ),
    );
  }
}