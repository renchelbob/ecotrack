import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:material_ui/material_ui.dart';

abstract final class const EcoTheme._() {
  static final ThemeData lightTheme = ThemeData(
    fontFamily: EcoTypography.fontFamily,
    textTheme: EcoTypography.textTheme,
    colorScheme: const ColorScheme.light(
      primary: EcoColors.inkPrimary,
      secondary: EcoColors.inkSecondary,
      surfaceContainerHighest: EcoColors.surfaceCard,
      surfaceContainerLow: EcoColors.surfaceSubtle,
      outline: EcoColors.borderMuted,
      error: EcoColors.inkPrimary,
    ),
    scaffoldBackgroundColor: EcoColors.surfacePrimary,
    appBarTheme: const AppBarTheme(
      backgroundColor: EcoColors.surfacePrimary,
      foregroundColor: EcoColors.inkPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: EcoTypography.headlineLarge,
    ),
    cardTheme: const CardThemeData(
      color: EcoColors.surfaceCard,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: EcoColors.borderMuted, width: 1.5),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: EcoColors.surfacePrimary,
      surfaceTintColor: EcoColors.surfacePrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: EcoColors.borderMuted,
      thickness: 1.5,
      space: 1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: EcoColors.inkPrimary,
        foregroundColor: EcoColors.surfacePrimary,
        disabledBackgroundColor: EcoColors.fillDisabled,
        disabledForegroundColor: EcoColors.inkSecondary,
        elevation: 0,
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
        textStyle: EcoTypography.bodyLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: EcoColors.surfacePrimary,
        foregroundColor: EcoColors.inkPrimary,
        disabledForegroundColor: EcoColors.inkSecondary,
        side: const BorderSide(color: EcoColors.inkPrimary, width: 1.5),
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
        textStyle: EcoTypography.bodyLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: EcoColors.inkPrimary,
        minimumSize: const Size(48, 48),
        textStyle: EcoTypography.bodyLarge,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: EcoColors.surfaceSubtle,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: EcoColors.borderMuted, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: EcoColors.borderMuted, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: EcoColors.inkPrimary, width: 1.5),
      ),
    ),
  );
}
