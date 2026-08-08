import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:froyou/app/froyou_app.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/debug/data/seed_data.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/services/services.dart';
import 'package:progressive_blur/progressive_blur.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    final (db, prefs, _) = await (
      AppDatabase.open(),
      SharedPreferences.getInstance(),
      // Awaited on purpose: the Home backdrop's blur shader is compiled here
      // rather than on the first frame, which otherwise renders unblurred and
      // then visibly snaps into place.
      ProgressiveBlurWidget.precache(),
    ).wait;

    // `flutter run --dart-define=SEED_DEMO=true` fills the database with
    // believable logs and working clusters. Worth having as a flag as well as
    // the Settings button: contextual embeddings don't exist in the Simulator,
    // so this is the only way to see the logs list and the analytics screen
    // populated there — and it makes the demo dataset reproducible.
    if (kDebugMode && const bool.fromEnvironment('SEED_DEMO')) {
      await DebugSeed.run(db.journalEntryDb);
    }

    final store = ProfileStore(prefs);

    // Both reads are synchronous — preferences are already in memory by now.
    // That is the point: the very first frame is themed from the user's image,
    // with no async gap and therefore no flash of the wrong colors.
    runApp(
      FroyouRoot(
        db: db,
        store: store,
        initialProfile: store.load(),
        initialPalette: store.loadPalette() ?? AppPalette.fallbackLight,
      ),
    );
  } catch (error, stackTrace) {
    AppLog.error('boot', 'startup failed', error, stackTrace);
    runApp(BootFailureApp(error: error));
  }
}
