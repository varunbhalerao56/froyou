import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Wraps the ObjectBox [Store] and exposes per-feature DB facades.
///
/// Single owner of the store handle. Features access their slice through
class AppDatabase {
  late final Store _store;
  late final JournalEntryDb _journalEntryDb;

  AppDatabase._create(this._store) {
    _journalEntryDb = JournalEntryDb(_store);
  }

  /// Wraps a store the caller already opened — an in-memory one, in practice.
  /// Lets widget tests drive the real repository instead of a stub.
  @visibleForTesting
  factory AppDatabase.forTesting(Store store) = AppDatabase._create;

  static Future<Directory> _storeDir() async {
    final Directory directory;

    if (Platform.isMacOS) {
      final supportDir = await getApplicationSupportDirectory();
      directory = Directory(p.join(supportDir.path, 'objectbox'));
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      directory = Directory(p.join(docsDir.path, 'objectbox'));
    }

    return directory;
  }

  static Future<Store> _openStore(Directory directory) => openStore(
    directory: directory.path,
    macosApplicationGroup: 'group.db.froyou',
  );

  static Future<AppDatabase> open() async {
    final directory = await _storeDir();

    try {
      final store = await _openStore(directory);
      AppLog.info('AppDatabase', 'store opened at ${directory.path}');
      return AppDatabase._create(store);
    } catch (e, stackTrace) {
      // A hot restart can leave the native store handle alive past the Dart
      // state that owned it. Re-attaching is the cheap fix and, unlike the
      // recreate path below, keeps the data.
      try {
        final store = Store.attach(getObjectBoxModel(), directory.path);
        AppLog.warn('AppDatabase', 're-attached to a store already open');
        return AppDatabase._create(store);
      } catch (_) {
        // Not an already-open store; fall through to the real recovery.
      }

      if (!kDebugMode) rethrow; // never silently destroy production data

      AppLog.error(
        'AppDatabase',
        'store open failed, recreating from scratch',
        e,
        stackTrace,
      );
      Store.removeDbFiles(directory.path);
      return AppDatabase._create(await _openStore(directory));
    }
  }

  /// Deletes the store from disk. The escape hatch offered on the boot-failure
  /// screen, for when a schema change has left an unopenable database behind.
  static Future<void> eraseLocalData() async {
    final directory = await _storeDir();
    Store.removeDbFiles(directory.path);
    AppLog.warn('AppDatabase', 'local data erased at ${directory.path}');
  }

  JournalEntryDb get journalEntryDb => _journalEntryDb;

  void close() {
    _store.close();
    AppLog.info('AppDatabase', 'store closed');
  }
}
