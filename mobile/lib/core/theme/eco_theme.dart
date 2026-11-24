import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:flutter/material.dart';

final class EcoColors {
  const EcoColors._();

  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryGreenLight = Color(0xFF81C784);
  static const Color darkBackground = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceVariant = Color(0xFF2A2A2A);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color accentOrange = Color(0xFFFF9800);
  static const Color accentBlue = Color(0xFF29B6F6);
  static const Color errorRed = Color(0xFFE53935);
  static const Color divider = Color(0xFF333333);
}

final class EcoTheme {
  const EcoTheme._();

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: EcoColors.primaryGreen,
      secondary: EcoColors.primaryGreenLight,
      surface: EcoColors.surface,
      error: EcoColors.errorRed,
    ),
    scaffoldBackgroundColor: EcoColors.darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: EcoColors.surface,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: EcoColors.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: EcoColors.primaryGreen,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
  );
}

/// Unified error banner presenter complying with negative constraint:
/// No raw SnackBar spam, deterministic action handling.
final class EcoErrorBannerPresenter {
  const EcoErrorBannerPresenter._();

  static void show(BuildContext context, AppError error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: switch (error.clientAction) {
            'queue_retry' => EcoColors.accentOrange,
            'show_banner' => EcoColors.errorRed,
            _ => EcoColors.surfaceVariant,
          },
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Row(
            children: [
              Icon(switch (error.clientAction) {
                'queue_retry' => Icons.cloud_off,
                'show_banner' => Icons.error_outline,
                _ => Icons.info_outline,
              }, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  error.uiMessageRu,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
