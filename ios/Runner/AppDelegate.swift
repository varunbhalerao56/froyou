import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the app's lifetime — the channels register handlers that capture
  /// these weakly, so letting them deallocate would silently stop every call
  /// from Dart from working.
  private let speechChannel = SpeechChannel()
  private let nlpChannel = NlpChannel()
  private let genAiChannel = GenAiChannel()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Must be live *before* plugins register: FlutterAppDelegate forwards
    // UNUserNotificationCenter callbacks on to plugins that added themselves as
    // application delegates, and flutter_local_notifications does exactly that
    // during registration below. Assigned here rather than in
    // `didFinishLaunchingWithOptions` for the same reason the channels are —
    // this is the UIScene-lifecycle template, which is the case the plugin's
    // own setup notes call out.
    //
    // Assigned directly, not via `as? UNUserNotificationCenterDelegate`:
    // FlutterAppDelegate conforms through FlutterAppLifeCycleProvider, so the
    // cast is unnecessary — and a conditional one would quietly become nil if
    // that ever changed, leaving taps that open nothing.
    UNUserNotificationCenter.current().delegate = self

    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Channel registration belongs here, not in `didFinishLaunchingWithOptions`.
    // This project uses Flutter's implicit-engine / SceneDelegate template, so
    // there is no `window.rootViewController as! FlutterViewController` to
    // reach at launch — the app-level binary messenger comes off the bridge.
    let messenger = engineBridge.applicationRegistrar.messenger()
    speechChannel.register(with: messenger)
    nlpChannel.register(with: messenger)
    genAiChannel.register(with: messenger)
  }
}
