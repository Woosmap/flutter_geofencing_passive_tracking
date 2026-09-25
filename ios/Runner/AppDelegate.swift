import UIKit
import Flutter
import geofencing_flutter_plugin

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Makes the app's plugins available inside the headless engine the plugin
    // spins up for onWoosmapRegionEvent. Without this the background isolate
    // has no method channels, and PoiResolver cannot read the POI from the
    // SDK's local database — it would fall back to the Store API over HTTP.
    //
    // iOS only: the Android background engine registers no plugins, so the
    // network path is the only one available there.
    GeofencingFlutterPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
