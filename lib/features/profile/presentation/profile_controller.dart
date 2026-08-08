import 'dart:io';

import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/profile/data/image_palette_service.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';

/// Owns the user's image + quote and the theme derived from them.
///
/// Sits above `MaterialApp` (see `AppScope`), so changing the backdrop in
/// Settings rethemes every route currently on the stack — and because
/// [AppColors.lerp] is implemented, the framework's built-in `AnimatedTheme`
/// makes that a transition rather than a jump.
class ProfileController extends ChangeNotifier {
  /// Callers pass `store:`, `profile:` and `palette:` — the private names here
  /// are initializing formals, which Dart maps to their public form.
  ProfileController({
    required this._store,
    required this._profile,
    required this._palette,
  });

  final ProfileStore _store;

  UserProfile _profile;
  AppPalette _palette;

  ImageProvider? _backdrop;
  String? _backdropPath;

  UserProfile get profile => _profile;
  AppPalette get palette => _palette;

  /// Memoized so the Home backdrop gets a stable, `==`-equal provider across
  /// rebuilds — otherwise every rebuild is a fresh cache key and Flutter
  /// re-decodes a full-screen image mid-animation.
  ImageProvider? get backdrop {
    final path = _profile.imagePath;
    if (path == null || path.isEmpty) return null;
    if (_backdropPath != path) {
      _backdropPath = path;
      _backdrop = FileImage(File(path));
    }
    return _backdrop;
  }

  /// Adopts a freshly picked image: copies it into app storage, re-derives the
  /// theme from it, and persists both. Applied immediately, so onboarding can
  /// preview the resulting theme before the user commits.
  Future<void> setBackdrop(String pickedPath) async {
    final storedPath = await _store.adoptBackdrop(pickedPath);
    final palette = await ImagePaletteService.derive(File(storedPath));

    _profile = _profile.copyWith(imagePath: storedPath);
    _palette = palette;
    await _store.save(_profile, _palette);
    notifyListeners();
  }

  Future<void> setQuote(String quote) async {
    _profile = _profile.copyWith(quote: quote.trim());
    await _store.save(_profile, _palette);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _profile = _profile.copyWith(onboarded: true);
    await _store.save(_profile, _palette);
    notifyListeners();
  }
}
