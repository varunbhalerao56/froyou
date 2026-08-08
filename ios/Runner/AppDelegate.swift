import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the app's lifetime — the channels register handlers that capture
  /// these weakly, so letting them deallocate would silently stop every call
  /// from Dart from working.
  private let speechChannel = SpeechChannel()
  private let nlpChannel = NlpChannel()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Channel registration belongs here, not in `didFinishLaunchingWithOptions`.
    // This project uses Flutter's implicit-engine / SceneDelegate template, so
    // there is no `window.rootViewController as! FlutterViewController` to
    // reach at launch — the app-level binary messenger comes off the bridge.
    let messenger = engineBridge.applicationRegistrar.messenger()
    speechChannel.register(with: messenger)
    nlpChannel.register(with: messenger)
  }
}
