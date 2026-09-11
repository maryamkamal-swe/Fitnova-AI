import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system and theme configurations for FitNova AI.
class AppTheme {
  static const Color background = Color(0xFF0F1015);
  static const Color surface = Color(0xFF17181F);
  static const Color surfaceElevated = Color(0xFF21222C);
  static const Color surfaceInteractive = Color(0xFF282A37);
  static const Color surfaceVariant = Color(0xFF282A36);
  static const Color primary = Color(0xFF38BDF8);
  static const Color onPrimary = Color(0xFF082F49);
  static const Color secondary = Color(0xFFF472B6);
  static const Color tertiary = Color(0xFFFED7AA);
  static const Color pastelPink = Color(0xFFFBCFE8);
  static const Color pastelSky = Color(0xFFBAE6FD);
  static const Color pastelLime = Color(0xFFD4F65B);
  static const Color textPrimary = Color(0xFFF5F6FA);
  static const Color textSecondary = Color(0xFF9E9EB4);
  static const Color textMuted = Color(0xFF696980);
  static const Color border = Color(0xFF282A36);
  static const Color borderStrong = Color(0xFF3D4052);
  static const Color error = Color(0xFFFDA4AF);
  static const Color success = Color(0xFF38BDF8);
  static const Color warning = Color(0xFFFED7AA);
  static const Color info = Color(0xFFBAE6FD);

  static final ValueNotifier<AccentTheme> accent =
      ValueNotifier<AccentTheme>(AccentTheme.babyBlue);

  static Color accentColor(AccentTheme value, {bool light = false}) {
    switch (value) {
      case AccentTheme.lightPink:
        return light ? const Color(0xFFDB2777) : secondary;
      case AccentTheme.lime:
        return light ? const Color(0xFF65A30D) : pastelLime;
      case AccentTheme.babyBlue:
        return light ? const Color(0xFF0284C7) : primary;
    }
  }

  /// Main Dark Material 3 Theme for FitNova AI
  static ThemeData darkTheme({AccentTheme accentTheme = AccentTheme.babyBlue}) {
    final accentColor = AppTheme.accentColor(accentTheme);
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.dark().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accentColor,
      colorScheme: ColorScheme.dark(
        primary: accentColor,
        onPrimary: accentTheme == AccentTheme.lightPink
         ? const Color(0xFF500724)
         : onPrimary,
        secondary: secondary,
        tertiary: tertiary,
        surface: surface,
        surfaceContainerHighest: surfaceInteractive,
        onSurface: textPrimary,
        error: error,
        onError: textPrimary,
        outline: border,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.bold,
        ),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: textPrimary,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: textSecondary,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: textSecondary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: textPrimary),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          color: textSecondary,
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          color: textSecondary,
          fontSize: 14,
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        errorStyle: GoogleFonts.plusJakartaSans(
          color: error,
          fontSize: 12,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: textSecondary,
          fontSize: 14,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle:
            GoogleFonts.plusJakartaSans(color: textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accentColor.withValues(alpha: 0.2),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.plusJakartaSans(
              color: accentColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return GoogleFonts.plusJakartaSans(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accentColor, size: 24);
          }
          return const IconThemeData(color: textSecondary, size: 24);
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentColor,
        linearTrackColor: surfaceVariant,
        circularTrackColor: surfaceVariant,
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
      ),
    );
  }
}

enum AccentTheme { babyBlue, lightPink, lime }
