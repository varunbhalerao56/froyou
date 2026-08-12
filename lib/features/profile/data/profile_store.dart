import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's backdrops and theme choices.
///
/// Reads are synchronous because [SharedPreferences] keeps everything in
/// memory once loaded — which is what lets `main()` theme the very first frame
/// with no async gap and therefore no flash of the wrong colours.
class ProfileStore {
  ProfileStore(this._prefs);

  final SharedPreferences _prefs;

  /// Where backdrop files live, resolved once at boot.
  ///
  /// Held rather than looked up per call because [ProfileController.providerFor]
  /// is synchronous — the carousel needs a provider during build, and an async
  /// hop there would mean a frame with no photo.
  String? _backdropDirPath;

  /// Resolves the backdrop directory. Call once, before [loadProfile].
  Future<void> init() async {
    _backdropDirPath = (await _backdropDir()).path;
  }

  /// Bumped whenever the stored shape changes. On a mismatch everything local
  /// is wiped rather than migrated — a deliberate call, since this is
  /// pre-release and migration code would outweigh the data it protects.
  static const int schemaVersion = 2;

  static const String _kSchemaVersion = 'app.schemaVersion';
  static const String _kProfile = 'profile.json';
  static const String _kThemeSettings = 'theme.settings';

  static const String _backdropDirName = 'backdrops';

  /// True on a fresh install too, which is harmless: there is nothing to wipe.
  bool get needsReset => (_prefs.getInt(_kSchemaVersion) ?? 0) != schemaVersion;

  /// Clears stored preferences and stamps the current version. The caller is
  /// responsible for erasing the database alongside it.
  Future<void> resetForNewSchema() async {
    await _prefs.clear();
    await _prefs.setInt(_kSchemaVersion, schemaVersion);
    await _deleteAllBackdropFiles();
    AppLog.warn('ProfileStore', 'local state reset to schema $schemaVersion');
  }

  /// The absolute path of a stored backdrop, for *right now*.
  ///
  /// Never persist what this returns. iOS moves an app's container between
  /// installs, so an absolute path written on one run can point into a
  /// directory that no longer exists on the next — which is exactly how every
  /// backdrop came back missing after a re-run.
  String absolutePathFor(String fileName) {
    final directory = _backdropDirPath;
    if (directory == null) return fileName;
    return p.join(directory, p.basename(fileName));
  }

  UserProfile loadProfile() {
    final raw = _prefs.getString(_kProfile);
    if (raw == null) return UserProfile.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return UserProfile.empty;
      final profile = UserProfile.fromJson(Map<String, Object?>.from(decoded));
      // Reduce whatever was stored to a bare file name. New writes are already
      // bare; this is what migrates the absolute paths older builds wrote,
      // without a schema bump, because the file itself never moved — only the
      // container around it did.
      return profile.copyWith(
        backdrops: [
          for (final backdrop in profile.backdrops)
            backdrop.copyWith(imagePath: p.basename(backdrop.imagePath)),
        ],
      );
    } catch (e) {
      AppLog.warn('ProfileStore', 'stored profile unreadable, ignoring: $e');
      return UserProfile.empty;
    }
  }

  ThemeSettings loadThemeSettings() {
    final raw = _prefs.getString(_kThemeSettings);
    if (raw == null) return ThemeSettings.defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return ThemeSettings.defaults;
      return ThemeSettings.fromJson(Map<String, Object?>.from(decoded));
    } catch (e) {
      AppLog.warn('ProfileStore', 'stored theme unreadable, ignoring: $e');
      return ThemeSettings.defaults;
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _prefs.setString(_kProfile, jsonEncode(profile.toJson()));
    // Only now that the surviving paths are durably recorded is it safe to
    // drop the files they replaced.
    unawaited(
      _pruneBackdropsExcept({
        for (final backdrop in profile.backdrops)
          p.basename(backdrop.imagePath),
      }),
    );
  }

  Future<void> saveThemeSettings(ThemeSettings settings) =>
      _prefs.setString(_kThemeSettings, jsonEncode(settings.toJson()));

  /// Generic key access, for the small caches other features keep (the pending
  /// follow-up question, reminder configuration) without each one needing its
  /// own store.
  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
  Future<void> remove(String key) => _prefs.remove(key);
  bool? getBool(String key) => _prefs.getBool(key);
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
  int? getInt(String key) => _prefs.getInt(key);
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  /// Copies a picked image into app storage and returns its new path.
  ///
  /// Copying is mandatory: `image_picker` hands back a path in a temp
  /// directory that iOS purges whenever it likes.
  ///
  /// The filename is timestamped rather than fixed, because [FileImage]'s cache
  /// key is the path alone — it never consults mtime. Reusing one name would
  /// leave Flutter serving the previous photo's decoded bitmap.
  Future<String> adoptBackdrop(String sourcePath) async {
    final directory = await _backdropDir();
    await directory.create(recursive: true);

    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final destination = p.join(
      directory.path,
      'backdrop_${DateTime.now().microsecondsSinceEpoch}$extension',
    );

    await File(sourcePath).copy(destination);
    // The name only. See [absolutePathFor].
    return p.basename(destination);
  }

  static Future<Directory> _backdropDir() async {
    // Application support, not documents: these are derived assets, so they
    // should not show up in the Files app or get swept into an iCloud backup.
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, _backdropDirName));
  }

  /// [keepNames] are bare file names, not paths — and that is the whole point.
  /// Comparing absolute paths here is what made a re-run delete every image:
  /// the stored paths carried the previous install's container id, so nothing
  /// matched anything on disk and the loop swept the directory clean.
  Future<void> _pruneBackdropsExcept(Set<String> keepNames) async {
    try {
      final directory = await _backdropDir();
      if (!directory.existsSync()) return;
      for (final entity in directory.listSync()) {
        if (entity is File && !keepNames.contains(p.basename(entity.path))) {
          await entity.delete();
        }
      }
    } catch (e) {
      // Leaving a stale image behind wastes a megabyte; failing here would
      // lose the user's new backdrop. Not worth propagating.
      AppLog.warn('ProfileStore', 'could not prune old backdrops: $e');
    }
  }

  Future<void> _deleteAllBackdropFiles() => _pruneBackdropsExcept(const {});
}
