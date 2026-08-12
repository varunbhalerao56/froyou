import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:froyou/app/froyou_app.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/debug/data/seed_data.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/services/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:progressive_blur/progressive_blur.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Holds the launch screen up across everything below rather than only across
  // engine start. Opening the database and compiling the blur shader take long
  // enough to see, and without this the storyboard is torn down the moment the
  // engine is ready — leaving a blank window until the first frame. The mark on
  // the launch screen sits on the Paper surface, which is what that first frame
  // paints, so the handover has nothing to give it away.
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    final prefs = await SharedPreferences.getInstance();
    final store = ProfileStore(prefs);
    // Before loadProfile, which rebases stored backdrops onto it.
    await store.init();

    // Wipe before opening the store, not after: the point is to start from a
    // clean database, and that can't be done while it's open.
    if (store.needsReset) {
      await store.resetForNewSchema();
      await AppDatabase.eraseLocalData();
    }

    final (db, _) = await (
      AppDatabase.open(),
      // Awaited on purpose: the Home backdrop's blur shader is compiled here
      // rather than on the first frame, which otherwise renders unblurred and
      // then visibly snaps into place.
      ProgressiveBlurWidget.precache(),
    ).wait;

    if (kDebugMode) {
      // Worth one line at boot: whether themes get named by the language model
      // or by the statistical fallback is invisible from the UI, and "the
      // labels look worse than I remember" is otherwise a hard thing to
      // diagnose.
      final genAi = await GenAiService.availability();
      AppLog.info(
        'boot',
        'genai available=${genAi.isAvailable}'
            '${genAi.reason == null ? '' : ' reason=${genAi.reason!.name}'}',
      );
    }

    if (kDebugMode && const bool.fromEnvironment('SEED_DEMO')) {
      await DebugSeed.run(db.journalEntryDb);
    }

    // Both reads are synchronous — preferences are already in memory by now.
    // That is the point: the very first frame is themed, with no async gap and
    // therefore no flash of the wrong colours.
    runApp(
      FroyouRoot(
        db: db,
        store: store,
        initialProfile: store.loadProfile(),
        initialThemeSettings: store.loadThemeSettings(),
        initialPlatformBrightness:
            PlatformDispatcher.instance.platformBrightness,
      ),
    );
  } catch (error, stackTrace) {
    AppLog.error('boot', 'startup failed', error, stackTrace);
    runApp(BootFailureApp(error: error));
  } finally {
    // In the `finally` because the failure path needs it just as much: a boot
    // that throws before `remove` leaves the first frame deferred forever, and
    // the app sits on the launch screen with no way to say what went wrong.
    FlutterNativeSplash.remove();
  }
}
