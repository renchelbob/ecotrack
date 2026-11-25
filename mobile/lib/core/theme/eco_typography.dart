import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:material_ui/material_ui.dart';

abstract final class const EcoTypography._() {
  static const String fontFamily = 'Inter';
  static const List<String> fontFamilyFallback = ['Roboto', 'SF Pro Text'];
  static const List<FontFeature> _tabularFeatures = [
    FontFeature.tabularFigures(),
  ];

  static const TextStyle displayHero = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 38 / 32,
    color: EcoColors.inkPrimary,
    fontFeatures: _tabularFeatures,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 30 / 24,
    color: EcoColors.inkPrimary,
    fontFeatures: _tabularFeatures,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 24 / 18,
    color: EcoColors.inkPrimary,
    fontFeatures: _tabularFeatures,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 22 / 16,
    color: EcoColors.inkPrimary,
    fontFeatures: _tabularFeatures,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: EcoColors.inkPrimary,
    fontFeatures: _tabularFeatures,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 16 / 12,
    color: EcoColors.inkSecondary,
    fontFeatures: _tabularFeatures,
  );

  static const TextStyle tabularMetric = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 24 / 20,
    color: EcoColors.inkPrimary,
    fontFeatures: _tabularFeatures,
  );

  static const TextTheme textTheme = TextTheme(
    displaySmall: displayHero,
    headlineLarge: headlineLarge,
    titleMedium: titleMedium,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    labelSmall: labelSmall,
  );
}
