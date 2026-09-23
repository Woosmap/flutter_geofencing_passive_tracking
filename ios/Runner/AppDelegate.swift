import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Nothing else to wire up: Woosmap region events are handled in Dart by the
    // background callback registered in lib/geofencing_service.dart.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
