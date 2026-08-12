import 'package:flutter/foundation.dart';

import 'backdrop.dart';

/// The images and captions the user set up, plus whether they've been through
/// onboarding.
///
/// The theme no longer lives here — it's [ThemeSettings], chosen independently
/// of the photos.
@immutable
class UserProfile {
  const UserProfile({
    this.backdrops = const [],
    this.onboarded = false,
    this.guidedLogDone = false,
  });

  final List<Backdrop> backdrops;
  final bool onboarded;

  /// Whether the guided first log has been offered.
  ///
  /// Separate from [onboarded] only so that being killed part-way through the
  /// last page doesn't offer it twice.
  final bool guidedLogDone;

  static const UserProfile empty = UserProfile();

  /// Beyond a handful, the crossfade cycle takes long enough that you rarely
  /// see the end of it.
  static const int maxBackdrops = 5;

  bool get hasBackdrop => backdrops.isNotEmpty;
  bool get isFull => backdrops.length >= maxBackdrops;

  /// Onboarding needs one image. Captions are optional.
  bool get isComplete => hasBackdrop;

  UserProfile copyWith({
    List<Backdrop>? backdrops,
    bool? onboarded,
    bool? guidedLogDone,
  }) {
    return UserProfile(
      backdrops: backdrops ?? this.backdrops,
      onboarded: onboarded ?? this.onboarded,
      guidedLogDone: guidedLogDone ?? this.guidedLogDone,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'backdrops': [for (final backdrop in backdrops) backdrop.toJson()],
    'onboarded': onboarded,
    'guidedLogDone': guidedLogDone,
  };

  factory UserProfile.fromJson(Map<String, Object?> json) {
    final raw = json['backdrops'];
    final onboarded = json['onboarded'] == true;
    return UserProfile(
      backdrops: raw is List
          ? [for (final entry in raw) ?Backdrop.tryFromJson(entry)]
          : const [],
      onboarded: onboarded,
      // Absent means the record predates this flag. Anyone already through
      // onboarding has effectively had the guided log, so default to their
      // onboarded state rather than to false — otherwise the next launch
      // ambushes an existing user with a first-run prompt.
      guidedLogDone: json['guidedLogDone'] is bool
          ? json['guidedLogDone']! as bool
          : onboarded,
    );
  }
}
