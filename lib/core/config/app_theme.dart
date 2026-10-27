import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Brand Emerald & Teal
  static const Color primary = Color(0xFF006948);
  static const Color primaryContainer = Color(0xFF00855D);
  static const Color primaryLight = Color(0xFF10B981);
  static const Color primaryFixed = Color(0xFF85F8C4);
  static const Color onPrimaryFixed = Color(0xFF002114);

  // Structural Slate
  static const Color slateNavy = Color(0xFF0F172A);
  static const Color slateCharcoal = Color(0xFF1E293B);
  static const Color secondary = Color(0xFF565E74);
  static const Color secondaryContainer = Color(0xFFDAE2FD);

  // Operational Alert & Pro Gold
  static const Color tertiary = Color(0xFF825100);
  static const Color tertiaryAmber = Color(0xFFF59E0B);
  static const Color tertiaryFixed = Color(0xFFFFDDB8);
  static const Color onTertiaryFixed = Color(0xFF2A1700);

  // Semantic
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color success = Color(0xFF059669);

  // Light Theme Surfaces
  static const Color lightSurface = Color(0xFFF8F9FF);
  static const Color lightSurfaceLow = Color(0xFFEFF4FF);
  static const Color lightSurfaceContainer = Color(0xFFE5EEFF);
  static const Color lightSurfaceHigh = Color(0xFFDCE9FF);
  static const Color lightSurfaceHighest = Color(0xFFD3E4FE);
  static const Color lightCard = Colors.white;
  static const Color lightOnSurface = Color(0xFF0B1C30);
  static const Color lightOnSurfaceVariant = Color(0xFF3D4A42);
  static const Color lightBorder = Color(0xFFE2E8F0);

  // Dark Theme Surfaces
  static const Color darkSurface = Color(0xFF0B1728);
  static const Color darkSurfaceLow = Color(0xFF132238);
  static const Color darkSurfaceContainer = Color(0xFF182B46);
  static const Color darkSurfaceHigh = Color(0xFF1F3554);
  static const Color darkSurfaceHighest = Color(0xFF274165);
  static const Color darkCard = Color(0xFF0F1D33);
  static const Color darkOnSurface = Color(0xFFF8FAFC);
  static const Color darkOnSurfaceVariant = Color(0xFF94A3B8);
  static const Color darkBorder = Color(0xFF1E293B);
}

class AppTheme {
  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: Colors.white,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: Color(0xFF131B2E),
        tertiary: AppColors.tertiary,
        onTertiary: Colors.white,
        tertiaryContainer: AppColors.tertiaryFixed,
        onTertiaryContainer: AppColors.onTertiaryFixed,
        error: AppColors.error,
        onError: Colors.white,
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightOnSurface,
        surfaceContainerLowest: AppColors.lightCard,
        surfaceContainerLow: AppColors.lightSurfaceLow,
        surfaceContainer: AppColors.lightSurfaceContainer,
        surfaceContainerHigh: AppColors.lightSurfaceHigh,
        surfaceContainerHighest: AppColors.lightSurfaceHighest,
        outline: Color(0xFF6D7A72),
        outlineVariant: AppColors.lightBorder,
      ),
      scaffoldBackgroundColor: AppColors.lightSurface,
      cardColor: AppColors.lightCard,
      dividerColor: AppColors.lightBorder,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightSurface.withValues(alpha: 0.95),
        foregroundColor: AppColors.lightOnSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.lightOnSurface,
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: GoogleFonts.plusJakartaSans(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: AppColors.lightOnSurface,
          letterSpacing: -0.02,
        ),
        headlineMedium: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.lightOnSurface,
          letterSpacing: -0.015,
        ),
        headlineSmall: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.lightOnSurface,
          letterSpacing: -0.01,
        ),
        titleMedium: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.lightOnSurface,
          letterSpacing: 0.01,
        ),
        bodyLarge: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.lightOnSurface,
        ),
        bodyMedium: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.lightOnSurface,
        ),
        bodySmall: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.lightOnSurfaceVariant,
        ),
        labelLarge: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.01,
        ),
        labelSmall: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.04,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightOnSurface,
          side: const BorderSide(color: AppColors.lightBorder),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: AppColors.lightOnSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.slateNavy,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.primaryLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        onPrimary: Color(0xFF002114),
        primaryContainer: AppColors.primary,
        onPrimaryContainer: Colors.white,
        secondary: Color(0xFF94A3B8),
        onSecondary: Color(0xFF0F172A),
        secondaryContainer: AppColors.darkSurfaceContainer,
        onSecondaryContainer: Color(0xFFDAE2FD),
        tertiary: AppColors.tertiaryAmber,
        onTertiary: Colors.black,
        tertiaryContainer: Color(0xFF653E00),
        onTertiaryContainer: Color(0xFFFFDDB8),
        error: AppColors.errorRed,
        onError: Colors.white,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkOnSurface,
        surfaceContainerLowest: AppColors.darkCard,
        surfaceContainerLow: AppColors.darkSurfaceLow,
        surfaceContainer: AppColors.darkSurfaceContainer,
        surfaceContainerHigh: AppColors.darkSurfaceHigh,
        surfaceContainerHighest: AppColors.darkSurfaceHighest,
        outline: Color(0xFF64748B),
        outlineVariant: AppColors.darkBorder,
      ),
      scaffoldBackgroundColor: AppColors.darkSurface,
      cardColor: AppColors.darkCard,
      dividerColor: AppColors.darkBorder,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkSurface.withValues(alpha: 0.95),
        foregroundColor: AppColors.darkOnSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.darkOnSurface,
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: GoogleFonts.plusJakartaSans(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: AppColors.darkOnSurface,
          letterSpacing: -0.02,
        ),
        headlineMedium: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.darkOnSurface,
          letterSpacing: -0.015,
        ),
        headlineSmall: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.darkOnSurface,
          letterSpacing: -0.01,
        ),
        titleMedium: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.darkOnSurface,
          letterSpacing: 0.01,
        ),
        bodyLarge: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.darkOnSurface,
        ),
        bodyMedium: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.darkOnSurface,
        ),
        bodySmall: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.darkOnSurfaceVariant,
        ),
        labelLarge: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.01,
        ),
        labelSmall: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.04,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: const Color(0xFF002114),
          minimumSize: const Size.fromHeight(48),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkOnSurface,
          side: const BorderSide(color: AppColors.darkBorder),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: AppColors.darkOnSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1E293B),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.primaryLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
