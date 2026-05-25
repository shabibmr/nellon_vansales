import 'package:flutter/material.dart';

/// Centralized Design System defining the color palette, typography constraints, and visual theme configurations.
///
/// Implements HSL-tailored vibrant accents, a modern light theme, and a sleek slate dark theme
/// to ensure unified layouts across the entire Van Sales application.
class AppTheme {
  // Vibrant HSL-Tailored Color Tokens
  
  /// Primary active accent color (Indigo).
  static const Color primaryIndigo = Color(0xFF6366F1);
  
  /// Darker shade of Indigo for elevated/active triggers.
  static const Color primaryDarkIndigo = Color(0xFF4F46E5);
  
  /// Semantic color for success (Emerald).
  static const Color successEmerald = Color(0xFF10B981);
  
  /// Semantic color for warnings or pending operations (Amber).
  static const Color warningAmber = Color(0xFFF59E0B);
  
  /// Semantic color for error validation/danger states (Rose).
  static const Color errorRose = Color(0xFFF43F5E);
  
  /// Accent info color (Sky blue).
  static const Color infoSky = Color(0xFF0EA5E9);

  // Sleek Dark Theme Color Palette
  
  /// Background color for scaffolding in dark mode (Slate 900).
  static const Color darkBackground = Color(0xFF0F172A);
  
  /// Surface/card background color in dark mode (Slate 800).
  static const Color darkSurface = Color(0xFF1E293B);
  
  /// Secondary surface background color in dark mode (Slate 700).
  static const Color darkCard = Color(0xFF334155);
  
  /// Main high-contrast text color in dark mode (Slate 50).
  static const Color darkText = Color(0xFFF8FAFC);
  
  /// Secondary subtitle text color in dark mode (Slate 400).
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  // Glassmorphism Theme Color Palette

  /// Primary gradient start color for glass background (Deep Indigo).
  static const Color glassBackground1 = Color(0xFF1A1040);

  /// Primary gradient end color for glass background (Deep Navy).
  static const Color glassBackground2 = Color(0xFF0D1B3E);

  /// Glass card surface color (white at 10% opacity).
  static const Color glassSurface = Color(0x1AFFFFFF);

  /// Glass card border color (white at 20% opacity).
  static const Color glassBorder = Color(0x33FFFFFF);

  /// Main text color on glass surfaces (Slate 100).
  static const Color glassText = Color(0xFFF1F5F9);

  /// Secondary text color on glass surfaces (Slate 300 blue-tint).
  static const Color glassTextSecondary = Color(0xFFBBC8E0);

  // Premium Light Theme Color Palette

  /// Background color for scaffolding in light mode (Slate 50).
  static const Color lightBackground = Color(0xFFF8FAFC);
  
  /// Surface/card background color in light mode.
  static const Color lightSurface = Color(0xFFFFFFFF);
  
  /// Main high-contrast text color in light mode (Slate 900).
  static const Color lightText = Color(0xFF0F172A);
  
  /// Secondary subtitle text color in light mode (Slate 500).
  static const Color lightTextSecondary = Color(0xFF64748B);

  // 1. Glassmorphism Theme definition
  static ThemeData get glassmorphismTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: glassBackground1,
      colorScheme: const ColorScheme.dark(
        primary: primaryIndigo,
        secondary: infoSky,
        surface: Colors.transparent,
        error: errorRose,
        onPrimary: Colors.white,
        onSurface: glassText,
      ),
      cardTheme: CardThemeData(
        color: glassSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: glassBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: glassText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: glassText),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDarkIndigo,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassSurface,
        hintStyle: const TextStyle(color: glassTextSecondary, fontSize: 14),
        labelStyle: const TextStyle(color: primaryIndigo, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: glassBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: glassBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryIndigo, width: 2),
        ),
      ),
    );
  }

  // 3. Sleek Dark Theme definition
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: primaryIndigo,
        secondary: infoSky,
        surface: darkSurface,
        error: errorRose,
        onPrimary: Colors.white,
        onSurface: darkText,
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: darkText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: darkText),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDarkIndigo,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        hintStyle: const TextStyle(color: darkTextSecondary, fontSize: 14),
        labelStyle: const TextStyle(color: primaryIndigo, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryIndigo, width: 2),
        ),
      ),
    );
  }

  // 4. Beautiful Light Theme definition
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: primaryIndigo,
        secondary: infoSky,
        surface: lightSurface,
        error: errorRose,
        onPrimary: Colors.white,
        onSurface: lightText,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 2,
        shadowColor: const Color(0x0F0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: lightText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: lightText),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDarkIndigo,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: lightTextSecondary, fontSize: 14),
        labelStyle: const TextStyle(color: primaryIndigo, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryIndigo, width: 2),
        ),
      ),
    );
  }
}
