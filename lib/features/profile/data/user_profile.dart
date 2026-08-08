import 'package:flutter/foundation.dart';

/// The two things the user sets in onboarding: an image that makes them feel
/// good, and a quote to go with it.
///
/// The image is more than decoration — the entire app theme is derived from it.
@immutable
class UserProfile {
  const UserProfile({this.imagePath, this.quote, this.onboarded = false});

  /// Absolute path into app support storage, not the picker's temp path.
  /// May point at a file that no longer exists — always guard.
  final String? imagePath;

  final String? quote;
  final bool onboarded;

  static const UserProfile empty = UserProfile();

  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;
  bool get hasQuote => quote != null && quote!.trim().isNotEmpty;

  /// Onboarding requires both — the theme comes from the image, and the quote
  /// is the whole point of the Home screen.
  bool get isComplete => hasImage && hasQuote;

  UserProfile copyWith({String? imagePath, String? quote, bool? onboarded}) {
    return UserProfile(
      imagePath: imagePath ?? this.imagePath,
      quote: quote ?? this.quote,
      onboarded: onboarded ?? this.onboarded,
    );
  }
}
