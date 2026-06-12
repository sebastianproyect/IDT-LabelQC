import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════
// lib/core/theme/app_theme.dart
// ═══════════════════════════════════════════════════════

class AppColors {
  // Background layers
  static const bg = Color(0xFF080A0F);
  static const surface = Color(0xFF161B24);
  static const surface2 = Color(0xFF1E2530);
  static const surface3 = Color(0xFF252D3A);
  static const border = Color(0xFF2A3344);

  // Brand
  static const accent = Color(0xFF00C8FF);
  static const accentDim = Color(0x1F00C8FF);

  // Status
  static const ok = Color(0xFF00E676);
  static const okBg = Color(0x1900E676);
  static const nok = Color(0xFFFF3D3D);
  static const nokBg = Color(0x19FF3D3D);
  static const warn = Color(0xFFFFB300);
  static const warnBg = Color(0x19FFB300);

  // Text
  static const textPrimary = Color(0xFFE8EDF5);
  static const textSecondary = Color(0xFF8A95A8);
  static const textMuted = Color(0xFF4D5A6E);

  // ISO Grades
  static const gradeA = Color(0xFF00E676);
  static const gradeB = Color(0xFF69F0AE);
  static const gradeC = Color(0xFFFFD740);
  static const gradeD = Color(0xFFFF6D00);
  static const gradeF = Color(0xFFFF3D3D);

  static Color forGrade(String grade) {
    switch (grade.toUpperCase()) {
      case 'A': return gradeA;
      case 'B': return gradeB;
      case 'C': return gradeC;
      case 'D': return gradeD;
      default: return gradeF;
    }
  }

  static Color bgForGrade(String grade) {
    switch (grade.toUpperCase()) {
      case 'A': return const Color(0x1900E676);
      case 'B': return const Color(0x1569F0AE);
      case 'C': return const Color(0x15FFD740);
      case 'D': return const Color(0x15FF6D00);
      default: return const Color(0x19FF3D3D);
    }
  }
}

class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          secondary: AppColors.ok,
          surface: AppColors.surface,
          error: AppColors.nok,
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: AppColors.textPrimary,
          onError: Colors.white,
        ),
        fontFamily: 'Inter',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -1),
          displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textMuted),
          labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.5),
          labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 1.2),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bg,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: AppColors.bg,
          ),
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.border,
          thickness: 1,
          space: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          hintStyle: const TextStyle(color: AppColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.black,
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.accent,
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors.textMuted,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? Colors.black : AppColors.textMuted),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? AppColors.accent : AppColors.surface3),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.surface2,
          contentTextStyle: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Inter'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          titleTextStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surface2,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.surface,
          modalBackgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0070CC),
          secondary: Color(0xFF00A855),
          surface: Colors.white,
          error: Color(0xFFD32F2F),
          onPrimary: Colors.white,
          onSurface: Color(0xFF1A1F2E),
        ),
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A1F2E),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      );
}

// ═══════════════════════════════════════════════════════
// lib/core/constants/app_constants.dart
// ═══════════════════════════════════════════════════════

class AppConstants {
  static const appName = 'LabelQC Pro';
  static const appVersion = '1.0.0';

  // Scan settings
  static const defaultScanTimeout = Duration(seconds: 30);
  static const analysisIsolateTimeout = Duration(seconds: 10);
  static const minAcceptableImageWidth = 200;
  static const minAcceptableImageHeight = 100;

  // SPC
  static const spcMinSamples = 3;
  static const spcWarningSamples = 5;
  static const spcFullAnalysisSamples = 10;

  // PDF
  static const pdfLogoMaxWidth = 120.0;
  static const pdfPageMargin = 40.0;

  // Sounds
  static const soundScanOk = 'assets/sounds/scan_ok.mp3';
  static const soundScanNok = 'assets/sounds/scan_nok.mp3';
  static const soundBeep = 'assets/sounds/scan_beep.mp3';
}
