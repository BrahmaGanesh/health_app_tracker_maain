import 'package:flutter/material.dart';

class AppColors {
  static const Color navy = Color(0xFF142D4C);
  static const Color mint = Color(0xFF9FD3C7);
  static const Color gold = Color(0xFFF8DA5B);
  static const Color lavender = Color(0xFFDCD6F7);
  static const Color violet = Color(0xFF4F3B78);
  static const Color peach = Color(0xFFEBCBAE);
  static const Color sage = Color(0xFF61B390);

  static const Color bgLight = Color(0xFFF0F4F8);
  static const Color bgDark = Color(0xFF0D1B2E);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF16243A);

  static const Color textPrimary = Color(0xFF142D4C);
  static const Color textMuted = Color(0xFF6B839E);
  static const Color textOnDark = Color(0xFFE8EDF5);

  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  static const Color bpNormal = Color(0xFF22C55E);
  static const Color bpElevated = Color(0xFFF59E0B);
  static const Color bpHigh = Color(0xFFEF4444);
  static const Color bpCrisis = Color(0xFFB91C1C);

  static const Color water = Color(0xFF0EA5E9);
  static const Color medicine = Color(0xFF8B5CF6);
  static const Color exercise = Color(0xFF047857);
  static const Color sleep = Color(0xFF7C3AED);
}

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bgLight,
      primaryColor: AppColors.navy,

      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.sage,
        brightness: Brightness.light,
        primary: AppColors.navy,
        secondary: AppColors.sage,
        surface: AppColors.cardLight,
      ),

      fontFamily: 'DMSans',

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgLight,
        foregroundColor: AppColors.navy,
        elevation: 0,
      ),

      cardTheme: const CardThemeData(
        color: AppColors.cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDark,
      primaryColor: AppColors.mint,

      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.sage,
        brightness: Brightness.dark,
        primary: AppColors.mint,
        secondary: AppColors.sage,
        surface: AppColors.cardDark,
      ),

      fontFamily: 'DMSans',

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgDark,
        foregroundColor: AppColors.textOnDark,
        elevation: 0,
      ),

      cardTheme: const CardThemeData(
        color: AppColors.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
    );
  }

  static Color bpStatusColor(String status) {
    switch (status) {
      case 'Normal':
        return AppColors.bpNormal;
      case 'Elevated':
        return AppColors.bpElevated;
      case 'High Stage 1':
      case 'High Stage 2':
        return AppColors.bpHigh;
      case 'Crisis':
        return AppColors.bpCrisis;
      default:
        return AppColors.textMuted;
    }
  }
}

class AppConfig {
  static const bool isProd = true; // Set to false for development, true for production

  static const String devBaseUrl = "http://10.0.2.2:5000";
  static const String prodBaseUrl = "https://health-app-tracker-maa.onrender.com";

  static String get baseUrl => isProd ? prodBaseUrl : devBaseUrl;

  static String get apiV1 => "$baseUrl/api/v1";
}