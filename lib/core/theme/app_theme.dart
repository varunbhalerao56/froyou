import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Builds the Material [ThemeData] for light and dark modes, plus a Cupertino
/// theme for iOS-feel widgets.
///
/// Each [ThemeData] registers the matching [AppColors] instance in its
/// extensions list so `context.appColors` resolves to the right palette at
/// runtime.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  /// The theme actually used at runtime: built from the palette derived from
  /// the user's backdrop image.
  ///
  /// Because [AppColors.lerp] is implemented, handing a new palette to
  /// [MaterialApp.theme] animates the whole app between color schemes through
  /// the framework's built-in `AnimatedTheme` — changing the image in Settings
  /// recolors everything with a transition, for free.
  static ThemeData fromPalette(AppPalette palette) =>
      _build(palette.colors, palette.brightness);

  static CupertinoThemeData cupertinoLight() =>
      _cupertino(AppColors.light, Brightness.light);
  static CupertinoThemeData cupertinoDark() =>
      _cupertino(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors palette, Brightness brightness) {
    final base = brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      brightness: brightness,
      scaffoldBackgroundColor: palette.background,
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: AppTypography.textTheme.apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      iconTheme: IconThemeData(color: palette.primary, size: AppSizes.iconMd),
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: brightness,
        surface: palette.background,
        primary: palette.primary,
        error: palette.error,
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        shadowColor: palette.cardShadow,
        shape: AppShapes.md,
        elevation: AppElevation.level3,
        surfaceTintColor: palette.card,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        elevation: AppElevation.level0,
        centerTitle: false,
        surfaceTintColor: palette.background,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.background,
          shape: AppShapes.md,
          elevation: AppElevation.level3,
          shadowColor: palette.shadow,
          minimumSize: const Size(64, AppSizes.buttonHeight),
          textStyle: AppTypography.body,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.background,
          shape: AppShapes.md,
          minimumSize: const Size(64, AppSizes.buttonHeight),
          textStyle: AppTypography.body,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.primary,
          shape: AppShapes.md,
          side: BorderSide(color: palette.border),
          minimumSize: const Size(64, AppSizes.buttonHeight),
          textStyle: AppTypography.body,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          shape: AppShapes.md,
          minimumSize: const Size(64, AppSizes.buttonHeight),
          textStyle: AppTypography.body,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.card,
        side: BorderSide(color: palette.border),
        labelStyle: AppTypography.subheadline.copyWith(
          color: palette.textPrimary,
        ),
        shape: AppShapes.lg,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.primary,
        contentTextStyle: AppTypography.body.copyWith(
          color: palette.background,
        ),
        shape: AppShapes.md,
        behavior: SnackBarBehavior.floating,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primary,
        foregroundColor: palette.background,
        shape: AppShapes.lg,
        elevation: AppElevation.level3,
        // Pin every FAB (regular + extended) to the shared button height so a
        // FAB and a Filled/Outlined button read at the same height.
        sizeConstraints: const BoxConstraints.tightFor(
          width: AppSizes.buttonHeight,
          height: AppSizes.buttonHeight,
        ),
        extendedSizeConstraints: const BoxConstraints.tightFor(
          height: AppSizes.buttonHeight,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: AppSpacing.md,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.border,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.primary,
        selectionColor: palette.primary.withValues(alpha: 0.2),
        selectionHandleColor: palette.primary,
      ),
    );
  }

  static CupertinoThemeData _cupertino(
    AppColors palette,
    Brightness brightness,
  ) {
    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: palette.primary,
      primaryContrastingColor: palette.background,
      scaffoldBackgroundColor: palette.background,
      barBackgroundColor: palette.background,
      textTheme: CupertinoTextThemeData(
        textStyle: AppTypography.body.copyWith(color: palette.textPrimary),
        actionTextStyle: AppTypography.callout.copyWith(color: palette.primary),
        tabLabelTextStyle: AppTypography.footnote.copyWith(
          color: palette.primary,
        ),
        navTitleTextStyle: AppTypography.headline.copyWith(
          color: palette.textPrimary,
        ),
        navLargeTitleTextStyle: AppTypography.largeTitle.copyWith(
          color: palette.textPrimary,
        ),
        navActionTextStyle: AppTypography.body.copyWith(color: palette.primary),
        pickerTextStyle: AppTypography.title3.copyWith(
          color: palette.textPrimary,
        ),
        dateTimePickerTextStyle: AppTypography.title3.copyWith(
          color: palette.textPrimary,
        ),
      ),
    );
  }
}
