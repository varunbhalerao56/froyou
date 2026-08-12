import 'package:flutter/foundation.dart';

/// Tagged logger built on [debugPrint]. Keeps logs short and grep-friendly
/// (`[Items] processing 5 items`).
///
/// Held to the [debugPrint] floor on purpose — release builds strip it out
/// automatically, and we don't want a heavier logging package in the bundle.
class AppLog {
  AppLog._();

  static void info(String tag, String message) {
    debugPrint('[$tag] $message');
  }

  static void warn(String tag, String message) {
    debugPrint('[$tag] ⚠️ $message');
  }

  static void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    debugPrint('[$tag] 🔥 $message');
    if (error != null) debugPrint('[$tag]    error=$error');
    if (stackTrace != null) debugPrint('[$tag]    $stackTrace');
  }
}
