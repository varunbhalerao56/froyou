import 'package:flutter/material.dart';

/// Color palette as a [ThemeExtension] so light and dark variants both register
/// on [ThemeData.extensions] and resolve through `Theme.of(context)`.
///
/// Widget code should read colors through [BuildContext.appColors] (see the
/// extension below). For ThemeData composition (where no BuildContext is
/// available) use the static [AppColors.light] / [AppColors.dark] instances
/// directly.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color primary;
  final Color background;
  final Color card;
  final Color textBox;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color placeholder;
  final Color error;
  final Color success;
  final Color logo;
  final Color shadow;
  final Color cardShadow;

  const AppColors({
    required this.primary,
    required this.background,
    required this.card,
    required this.textBox,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.placeholder,
    required this.error,
    required this.success,
    required this.logo,
    required this.shadow,
    required this.cardShadow,
  });

  /// Light palette — current Chuck'it look. Values preserved verbatim from
  /// the legacy `UIColors` so the visual identity stays intact through the
  /// rebuild.
  static const AppColors light = AppColors(
    primary: Color(0xFF333A56),
    background: Color(0xFFFAFAF6),
    card: Color(0xFFF4F2EE),
    textBox: Color(0xFFF0EDE8),
    border: Color(0xFFE0E0E0),
    textPrimary: Color(0xFF333A56),
    textSecondary: Color(0xFF7A809C),
    placeholder: Color(0xFFA5A8BA),
    error: Color(0xFFFF5252),
    success: Color(0xFF44A1A0),
    logo: Color(0xFFFFCD5D),
    shadow: Color.fromARGB(120, 10, 0, 0),
    cardShadow: Color.fromARGB(60, 10, 0, 0),
  );

  /// Dark palette — first pass. Primary stays in the same hue family for
  /// brand recognition but lifts toward a softer blue so it reads on dark
  /// surfaces. Card surfaces are ~8% lighter than the background for
  /// elevation hierarchy. Phase 10 will fine-tune contrast.
  static const AppColors dark = AppColors(
    primary: Color(0xFF8B98C8),
    background: Color(0xFF0E0F14),
    card: Color(0xFF1A1B22),
    textBox: Color(0xFF22232C),
    border: Color(0xFF2A2C36),
    textPrimary: Color(0xFFF5F5F1),
    textSecondary: Color(0xFFC3C6D4),
    placeholder: Color(0xFF6E7180),
    error: Color(0xFFFF6B6B),
    success: Color(0xFF5FB8B7),
    logo: Color(0xFFFFCD5D),
    shadow: Color.fromARGB(180, 0, 0, 0),
    cardShadow: Color.fromARGB(90, 0, 0, 0),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? background,
    Color? card,
    Color? textBox,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? placeholder,
    Color? error,
    Color? success,
    Color? logo,
    Color? shadow,
    Color? cardShadow,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      background: background ?? this.background,
      card: card ?? this.card,
      textBox: textBox ?? this.textBox,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      placeholder: placeholder ?? this.placeholder,
      error: error ?? this.error,
      success: success ?? this.success,
      logo: logo ?? this.logo,
      shadow: shadow ?? this.shadow,
      cardShadow: cardShadow ?? this.cardShadow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      textBox: Color.lerp(textBox, other.textBox, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      logo: Color.lerp(logo, other.logo, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
    );
  }
}

/// Read [AppColors] from the surrounding [Theme] via a single short form.
///
/// ```dart
/// context.appColors.primary
/// ```
///
/// Falls back to [AppColors.light] if the extension is missing — keeps tests
/// and any standalone widget rendering from crashing.
extension AppColorsContext on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
