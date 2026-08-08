import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's backdrop image, quote, and the palette derived from
/// that image.
///
/// Reads are synchronous because [SharedPreferences] keeps everything in
/// memory once loaded — which is what lets `main()` theme the very first frame
/// with no async gap and therefore no color flash on relaunch.
class ProfileStore {
  ProfileStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _kImagePath = 'profile.imagePath';
  static const String _kQuote = 'profile.quote';
  static const String _kOnboarded = 'profile.onboarded';
  static const String _kPalette = 'profile.paletteJson';

  static const String _backdropDirName = 'backdrops';

  UserProfile load() => UserProfile(
    imagePath: _prefs.getString(_kImagePath),
    quote: _prefs.getString(_kQuote),
    onboarded: _prefs.getBool(_kOnboarded) ?? false,
  );

  /// Null when nothing is stored, or when the stored payload is from an older
  /// schema. Callers fall back to [AppPalette.fallbackLight].
  AppPalette? loadPalette() {
    final raw = _prefs.getString(_kPalette);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AppPalette.tryFromJson(Map<String, Object?>.from(decoded));
    } catch (e) {
      AppLog.warn('ProfileStore', 'stored palette unreadable, ignoring: $e');
      return null;
    }
  }

  Future<void> save(UserProfile profile, AppPalette palette) async {
    await Future.wait([
      if (profile.imagePath != null)
        _prefs.setString(_kImagePath, profile.imagePath!)
      else
        _prefs.remove(_kImagePath),
      if (profile.quote != null)
        _prefs.setString(_kQuote, profile.quote!)
      else
        _prefs.remove(_kQuote),
      _prefs.setBool(_kOnboarded, profile.onboarded),
      _prefs.setString(_kPalette, jsonEncode(palette.toJson())),
    ]);

    // Only now that the new path is durably recorded is it safe to drop the
    // files it replaced.
    unawaited(_pruneBackdropsExcept(profile.imagePath));
  }

  /// Copies a picked image into app storage and returns its new path.
  ///
  /// Copying is mandatory: `image_picker` hands back a path in a temp
  /// directory that iOS purges whenever it likes.
  ///
  /// The filename is timestamped rather than fixed, because [FileImage]'s cache
  /// key is the path alone — it never consults mtime. Reusing one
  /// `backdrop.jpg` would leave Flutter serving the previous photo's decoded
  /// bitmap under the newly derived palette.
  Future<String> adoptBackdrop(String sourcePath) async {
    final directory = await _backdropDir();
    await directory.create(recursive: true);

    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final destination = p.join(
      directory.path,
      'backdrop_${DateTime.now().millisecondsSinceEpoch}$extension',
    );

    await File(sourcePath).copy(destination);
    return destination;
  }

  static Future<Directory> _backdropDir() async {
    // Application support, not documents: this is a derived asset, so it should
    // not show up in the Files app or get swept into an iCloud backup.
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, _backdropDirName));
  }

  Future<void> _pruneBackdropsExcept(String? keepPath) async {
    try {
      final directory = await _backdropDir();
      if (!directory.existsSync()) return;
      for (final entity in directory.listSync()) {
        if (entity is File && entity.path != keepPath) {
          await entity.delete();
        }
      }
    } catch (e) {
      // Leaving a stale image behind wastes a megabyte; failing here would
      // lose the user's new backdrop. Not worth propagating.
      AppLog.warn('ProfileStore', 'could not prune old backdrops: $e');
    }
  }
}
