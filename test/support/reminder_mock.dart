import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// The plugin's own channel name. Not exported by the package, so it is
/// repeated here; if it ever changes, these mocks go quiet rather than failing
/// loudly, which is why the service's tests assert on recorded calls.
const String notificationsChannel = 'dexterous.com/flutter/local_notifications';
const String timezoneChannel = 'flutter_timezone';

/// Stubs both channels reminders depend on.
///
/// Same reasoning as the genai and speech mocks: an unmocked method channel
/// never answers under a widget test's fake clock, so anything awaiting one
/// hangs to its timeout rather than failing.
///
/// [calls] collects everything sent to the notification channel, which is how
/// the service's tests check what was scheduled without a real notification
/// centre.
void mockNotifications({
  bool granted = true,
  String timeZone = 'UTC',
  List<MethodCall>? calls,
}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(
    const MethodChannel(notificationsChannel),
    (call) async {
      calls?.add(call);
      switch (call.method) {
        case 'requestPermissions':
          return granted;
        case 'checkPermissions':
          return <String, Object?>{
            'isEnabled': granted,
            'isAlertEnabled': granted,
            'isSoundEnabled': granted,
            'isBadgeEnabled': false,
          };
        default:
          return null;
      }
    },
  );

  messenger.setMockMethodCallHandler(
    const MethodChannel(timezoneChannel),
    (call) async => call.method == 'getLocalTimezone' ? timeZone : null,
  );
}

void unmockNotifications() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel(notificationsChannel),
    null,
  );
  messenger.setMockMethodCallHandler(const MethodChannel(timezoneChannel), null);
  debugDefaultTargetPlatformOverride = null;
}

/// Puts the plugin on its iOS code path.
///
/// Two things are missing in a host test. `GeneratedPluginRegistrant` never
/// runs, so the platform instance is never assigned; and every branch in the
/// plugin keys off `defaultTargetPlatform`, which is Android under test — so
/// `resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>`
/// returns null and `initialize` rejects iOS-only settings.
///
/// Opt-in rather than folded into [mockNotifications], because the override
/// also changes scroll physics and page transitions — which suites that merely
/// need the channel to answer should not have to absorb.
void useIosNotificationPlatform() {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  IOSFlutterLocalNotificationsPlugin.registerWith();
}
