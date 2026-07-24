import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Keep a strong reference so the observer stays registered for the app's lifetime.
  let objReceiver = GeofencingEventsReceiver()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Start listening for Woosmap geofence region events.
    objReceiver.startReceivingEvent()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
