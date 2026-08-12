import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';

/// Loads the app's bundled font into the test binding.
///
/// `flutter_test` does not load fonts declared in pubspec, so without this
/// every golden renders in the fallback face and tells you nothing about type
/// size, weight or line breaks — which is most of what these goldens exist to
/// check.
Future<void> loadAppFonts() async {
  final loader = FontLoader(AppTypography.fontFamily);
  for (final weight in const ['Regular', 'Medium', 'Semibold', 'Bold']) {
    final file = File('fonts/SF-Pro-Rounded-$weight.otf');
    if (!file.existsSync()) continue;
    loader.addFont(
      file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
}
