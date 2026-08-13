import 'dart:io';

import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/home/presentation/home_layout.dart';
import 'package:froyou/features/profile/data/backdrop.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';

/// Owns the user's backdrops and their theme.
///
/// Sits above `MaterialApp` (see `AppScope`), so a theme change rethemes every
/// route currently on the stack — and because [AppColors.lerp] is implemented,
/// the framework's built-in `AnimatedTheme` makes that a transition rather than
/// a jump.
class ProfileController extends ChangeNotifier {
  /// Callers pass `store:`, `profile:`, `themeSettings:` and
  /// `platformBrightness:` — the private names are initializing formals, which
  /// Dart maps to their public form.
  ProfileController({
    required this._store,
    required this._profile,
    required this._themeSettings,
    required this._platformBrightness,
  }) {
    _palette = AppPalette.fromSettings(_themeSettings, _platformBrightness);
    // Read here rather than threaded in as a fourth `initial*` parameter:
    // preferences are already in memory by the time this is built, so the
    // synchronous-first-frame guarantee holds either way, and every existing
    // call site keeps compiling.
    _homeLayout = HomeLayout.fromName(_store.getString(_kHomeLayout));
  }

  static const String _kHomeLayout = 'home.layout';

  final ProfileStore _store;

  UserProfile _profile;
  ThemeSettings _themeSettings;
  Brightness _platformBrightness;
  late AppPalette _palette;
  late HomeLayout _homeLayout;

  final Map<String, ImageProvider> _providers = {};

  UserProfile get profile => _profile;
  ThemeSettings get themeSettings => _themeSettings;
  AppPalette get palette => _palette;

  List<Backdrop> get backdrops => _profile.backdrops;

  /// Memoized per path so the carousel gets stable, `==`-equal providers across
  /// rebuilds — otherwise every rebuild is a fresh cache key and Flutter
  /// re-decodes full-screen images mid-crossfade.
  ImageProvider providerFor(Backdrop backdrop) =>
      _providers[backdrop.imagePath] ??= FileImage(
        File(_store.absolutePathFor(backdrop.imagePath)),
      );

  /// Called when iOS switches appearance. Only does work in `system` mode, so
  /// a user pinned to light or dark never gets a spurious rebuild.
  void setPlatformBrightness(Brightness brightness) {
    if (_platformBrightness == brightness) return;
    _platformBrightness = brightness;
    if (_themeSettings.brightnessMode != ThemeBrightnessMode.system) return;
    _rebuildPalette();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Theme
  // ---------------------------------------------------------------------------

  Future<void> updateTheme(ThemeSettings settings) async {
    _themeSettings = settings;
    _rebuildPalette();
    notifyListeners();
    await _store.saveThemeSettings(settings);
  }

  Future<void> setPreset(String presetId) =>
      updateTheme(_themeSettings.copyWith(presetId: presetId));

  Future<void> setBrightnessMode(ThemeBrightnessMode mode) =>
      updateTheme(_themeSettings.copyWith(brightnessMode: mode));

  Future<void> setBackgroundTint(double tint) =>
      updateTheme(_themeSettings.copyWith(backgroundTint: tint));

  void _rebuildPalette() {
    _palette = AppPalette.fromSettings(_themeSettings, _platformBrightness);
  }

  // ---------------------------------------------------------------------------
  // Home layout
  // ---------------------------------------------------------------------------

  /// Deliberately owned here, unlike the reminder settings: this one *must*
  /// repaint the shell as it changes, and this controller sits above
  /// `MaterialApp` — so switching from the debug menu recomposes the Home
  /// behind it, which is the entire point of a live gallery.
  HomeLayout get homeLayout => _homeLayout;

  Future<void> setHomeLayout(HomeLayout layout) async {
    if (_homeLayout == layout) return;
    _homeLayout = layout;
    notifyListeners();
    await _store.setString(_kHomeLayout, layout.name);
  }

  // ---------------------------------------------------------------------------
  // Backdrops
  // ---------------------------------------------------------------------------

  /// Copies a picked image into app storage and appends it. Silently ignored
  /// once the list is full — the UI hides the add control at that point.
  Future<void> addBackdrop(String pickedPath, {String? caption}) async {
    if (_profile.isFull) return;
    final storedPath = await _store.adoptBackdrop(pickedPath);
    await _writeProfile(
      _profile.copyWith(
        backdrops: [
          ..._profile.backdrops,
          Backdrop(imagePath: storedPath, caption: caption),
        ],
      ),
    );
  }

  /// Framing is per image and non-destructive — nothing is re-encoded, so
  /// putting it back where it started restores the original exactly.
  ///
  /// Every call writes the whole profile to preferences, so this takes a
  /// finished framing rather than a field at a time: the editor commits when a
  /// gesture ends, not while a finger is moving.
  Future<void> setFraming(int index, BackdropFraming framing) async {
    if (index < 0 || index >= _profile.backdrops.length) return;
    if (_profile.backdrops[index].framing == framing) return;
    final updated = [..._profile.backdrops];
    updated[index] = updated[index].copyWith(framing: framing);
    await _writeProfile(_profile.copyWith(backdrops: updated));
  }

  Future<void> setCaption(int index, String? caption) async {
    if (index < 0 || index >= _profile.backdrops.length) return;
    final trimmed = caption?.trim();
    final updated = [..._profile.backdrops];
    // copyWith rather than a fresh Backdrop: rebuilding one from its path and
    // its caption is how naming a picture used to silently reset how it sits.
    updated[index] = updated[index].copyWith(
      caption: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
    await _writeProfile(_profile.copyWith(backdrops: updated));
  }

  Future<void> removeBackdrop(int index) async {
    if (index < 0 || index >= _profile.backdrops.length) return;
    final updated = [..._profile.backdrops]..removeAt(index);
    await _writeProfile(_profile.copyWith(backdrops: updated));
  }

  Future<void> reorderBackdrops(int oldIndex, int newIndex) async {
    final updated = [..._profile.backdrops];
    if (oldIndex < 0 || oldIndex >= updated.length) return;
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex.clamp(0, updated.length), moved);
    await _writeProfile(_profile.copyWith(backdrops: updated));
  }

  // ---------------------------------------------------------------------------
  // Onboarding handoff
  // ---------------------------------------------------------------------------

  bool _guidedLogRequested = false;

  /// Finishes onboarding, optionally asking Home to open the recorder as soon
  /// as it appears.
  ///
  /// [startRecording] is set *before* the profile write on purpose: writing is
  /// what flips the root from onboarding to the shell, so setting it first
  /// means the shell can consume the request on its very first build — one
  /// notification, no extra frame, and no window where Home is up but the
  /// request hasn't landed.
  Future<void> completeOnboarding({bool startRecording = false}) {
    _guidedLogRequested = startRecording;
    return _writeProfile(
      _profile.copyWith(onboarded: true, guidedLogDone: true),
    );
  }

  /// Whether Home should open the recorder, clearing the request as it reads.
  ///
  /// Deliberately not persisted and deliberately single-shot: a rebuild must
  /// not reopen the recorder over someone already typing.
  bool consumeGuidedLogRequest() {
    if (!_guidedLogRequested) return false;
    _guidedLogRequested = false;
    return true;
  }

  Future<void> _writeProfile(UserProfile profile) async {
    _profile = profile;
    // Drop providers for images no longer referenced, so the cache doesn't
    // pin decoded bitmaps for deleted files.
    final live = {for (final b in profile.backdrops) b.imagePath};
    _providers.removeWhere((path, _) => !live.contains(path));

    notifyListeners();
    await _store.saveProfile(profile);
  }
}
