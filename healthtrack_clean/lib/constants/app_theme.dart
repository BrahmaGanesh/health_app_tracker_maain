// ============================================================
// lib/constants/app_theme.dart — HealthTrack Theme (Fixed)
// ✅ Bottom nav visible in both light/dark
// ✅ Dark mode full support
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // ── Brand (Locked Palette) ────────────────────────────────────
  static const Color navy     = Color(0xFF142D4C);
  static const Color mint     = Color(0xFF9FD3C7);
  static const Color gold     = Color(0xFFF8DA5B);
  static const Color lavender = Color(0xFFDCD6F7);
  static const Color violet   = Color(0xFF4F3B78);
  static const Color peach    = Color(0xFFEBCBAE);
  static const Color sage     = Color(0xFF61B390);

  // ── Backgrounds ───────────────────────────────────────────────
  static const Color bgLight   = Color(0xFFF0F4F8);
  static const Color bgDark    = Color(0xFF0D1B2E);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark  = Color(0xFF16243A);
  static const Color navLight  = Color(0xFFFFFFFF);
  static const Color navDark   = Color(0xFF111E2E);

  // ── Text ──────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF142D4C);
  static const Color textMuted   = Color(0xFF6B839E);
  static const Color textOnDark  = Color(0xFFE8EDF5);
  static const Color textMutedDark = Color(0xFF7A9BB8);

  // ── Status ────────────────────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger  = Color(0xFFEF4444);
  static const Color info    = Color(0xFF3B82F6);

  // ── BP Status ─────────────────────────────────────────────────
  static const Color bpNormal   = Color(0xFF22C55E);
  static const Color bpElevated = Color(0xFFF59E0B);
  static const Color bpHigh     = Color(0xFFEF4444);
  static const Color bpCrisis   = Color(0xFFB91C1C);

  // ── Feature Colors ────────────────────────────────────────────
  static const Color water    = Color(0xFF0EA5E9);
  static const Color medicine = Color(0xFF8B5CF6);
  static const Color exercise = Color(0xFF047857);
  static const Color sleep    = Color(0xFF7C3AED);
  static const Color sugar    = Color(0xFFF59E0B);
  static const Color document = Color(0xFF4F3B78);
}

class AppTheme {
  // ══════════════════════════════════════════════════════════════
  // LIGHT THEME
  // ══════════════════════════════════════════════════════════════
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bgLight,
      primaryColor: AppColors.navy,
      colorScheme: const ColorScheme.light(
        primary:   AppColors.navy,
        secondary: AppColors.sage,
        surface:   AppColors.cardLight,
        error:     AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: AppColors.navy,
        onSurface: AppColors.textPrimary,
      ),
      fontFamily: 'DMSans',
      textTheme: const TextTheme(
        displayLarge:  TextStyle(fontFamily:'Fraunces', fontWeight:FontWeight.w900, color:AppColors.textPrimary),
        headlineLarge: TextStyle(fontFamily:'Fraunces', fontWeight:FontWeight.bold, color:AppColors.textPrimary),
        headlineMedium:TextStyle(fontFamily:'Fraunces', fontWeight:FontWeight.bold, color:AppColors.textPrimary),
        headlineSmall: TextStyle(fontFamily:'Fraunces', fontWeight:FontWeight.bold, color:AppColors.textPrimary),
        titleLarge:    TextStyle(fontFamily:'Fraunces', fontWeight:FontWeight.bold, color:AppColors.textPrimary),
        bodyLarge:     TextStyle(color:AppColors.textPrimary),
        bodyMedium:    TextStyle(color:AppColors.textPrimary),
        bodySmall:     TextStyle(color:AppColors.textMuted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgLight,
        foregroundColor: AppColors.navy,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.sage,
          foregroundColor: AppColors.navy,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.mint, width: 2),
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
      ),
      // ── BOTTOM NAV — LIGHT ────────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.navLight,
        selectedItemColor: AppColors.navy,       // dark navy = clearly visible
        unselectedItemColor: Color(0xFFADB8C6),  // medium grey
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      dividerColor: Colors.grey.shade200,
      iconTheme: const IconThemeData(color: AppColors.navy),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // DARK THEME
  // ══════════════════════════════════════════════════════════════
  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDark,
      primaryColor: AppColors.mint,
      colorScheme: const ColorScheme.dark(
        primary:    AppColors.mint,
        secondary:  AppColors.sage,
        surface:    AppColors.cardDark,
        error:      AppColors.danger,
        onPrimary:  AppColors.navy,
        onSecondary: Colors.white,
        onSurface:  AppColors.textOnDark,
      ),
      fontFamily: 'DMSans',
      textTheme: const TextTheme(
        displayLarge:  TextStyle(fontFamily:'Fraunces', fontWeight:FontWeight.w900, color:AppColors.textOnDark),
        headlineLarge: TextStyle(fontFamily:'Fraunces', fontWeight:FontWeight.bold, color:AppColors.textOnDark),
        headlineMedium:TextStyle(fontFamily:'Fraunces', fontWeight:FontWeight.bold, color:AppColors.textOnDark),
        headlineSmall: TextStyle(fontFamily:'Fraunces', fontWeight:FontWeight.bold, color:AppColors.textOnDark),
        titleLarge:    TextStyle(fontFamily:'Fraunces', fontWeight:FontWeight.bold, color:AppColors.textOnDark),
        bodyLarge:     TextStyle(color:AppColors.textOnDark),
        bodyMedium:    TextStyle(color:AppColors.textOnDark),
        bodySmall:     TextStyle(color:AppColors.textMutedDark),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cardDark,
        foregroundColor: AppColors.textOnDark,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF1E3250)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.sage,
          foregroundColor: AppColors.navy,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1A2E45),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E3250)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E3250)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.mint, width: 2),
        ),
        hintStyle: const TextStyle(color: AppColors.textMutedDark, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.textMutedDark, fontSize: 12, fontWeight: FontWeight.w700),
      ),
      // ── BOTTOM NAV — DARK ─────────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.navDark,
        selectedItemColor: AppColors.mint,          // bright mint = visible on dark
        unselectedItemColor: Color(0xFF4A6580),     // dim blue-grey
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      dividerColor: const Color(0xFF1E3250),
      iconTheme: const IconThemeData(color: AppColors.textOnDark),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────
  static Color bpStatusColor(String status) {
    switch (status) {
      case 'Normal':      return AppColors.bpNormal;
      case 'Elevated':    return AppColors.bpElevated;
      case 'High Stage 1':
      case 'High Stage 2':return AppColors.bpHigh;
      case 'Crisis':      return AppColors.bpCrisis;
      default:            return AppColors.textMuted;
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