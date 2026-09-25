import 'package:flutter/material.dart';
import 'package:geofencing_flutter_plugin/geofencing_flutter_plugin.dart';

import 'geofence_event_forwarder.dart';

/// Your Woosmap private API key. Replace this placeholder with your own key —
/// or, for production, inject it at runtime (e.g. from secure storage or a
/// build-time environment variable) instead of hardcoding it here.
const String kWoosmapPrivateApiKey = 'YOUR_WOOSMAP_PRIVATE_API_KEY';

/// Thin wrapper around the Woosmap Geofencing Flutter plugin.
///
/// Everything happens in Dart: this class initializes the plugin, starts the
/// `passiveTracking` profile, and registers [onWoosmapRegionEvent] as the
/// background region callback. The plugin then wakes that callback in a
/// background isolate for every region event (enter/exit), including when the
/// application has been terminated — no native receiver is needed.
class GeofencingService {
  final GeofencingFlutterPlugin _geofencing = GeofencingFlutterPlugin();

  /// Current Woosmap location-permission status, one of:
  /// `GRANTED_BACKGROUND`, `GRANTED_FOREGROUND`, `DENIED`, `UNKNOWN`.
  Future<String?> permissionStatus() => _geofencing.getPermissionsStatus();

  /// Ask the OS for location permission via the plugin.
  ///
  /// [background] requests "Always"/background access (needed for
  /// passiveTracking); when false it requests foreground ("When In Use").
  /// Returns the resulting status string (see [permissionStatus]).
  Future<String?> requestPermission({bool background = false}) =>
      _geofencing.requestPermissions(withBackgroundAccess: background);

  /// Initialize the plugin and start passive tracking.
  ///
  /// Call this only AFTER the user has granted location permission
  /// (WhenInUse, then Always for background/passive tracking).
  ///
  /// [woosmapApiKey] is your Woosmap private API key; it defaults to
  /// [kWoosmapPrivateApiKey] but can be overridden by the caller.
  Future<void> initAndStart({
    String woosmapApiKey = kWoosmapPrivateApiKey,
  }) async {
    // 1. Initialize the plugin.
    //    privateKeyWoosmapAPI authenticates against the Woosmap API.
    //    protectedRegionSlot is optional: on iOS it reserves up to 3 of the
    //    20 CLRegion slots for a third-party plugin. Set to 0 if not needed.
    try {
      final WoosmapGeofencingOptions options = WoosmapGeofencingOptions(
        privateKeyWoosmapAPI: woosmapApiKey,
        protectedRegionSlot: 0,
      );
      final String? initResult = await _geofencing.initialize(options);
      debugPrint('Woosmap init: $initResult');
    } catch (e) {
      debugPrint('Woosmap init error: $e');
      return;
    }

    // 2. Start passive tracking.
    //    Accepted profiles: liveTracking, passiveTracking,
    //    optimalPassiveTracking, visitsTracking, beaconTracking.
    try {
      final String? result = await _geofencing.startTracking('passiveTracking');
      debugPrint('startTracking(passiveTracking): $result');
    } catch (e) {
      debugPrint('startTracking error: $e');
      return;
    }

    // 3. Register the background region callback.
    //    It must come after startTracking: stopTracking() removes a registered
    //    callback, since tracking is what produces the region events.
    await registerBackgroundCallback();
  }

  /// Register [onWoosmapRegionEvent] as the background region callback, unless
  /// one is already registered.
  ///
  /// The registration is persisted natively, so it survives an application
  /// restart; this is a no-op when it is still in place.
  Future<bool> registerBackgroundCallback() async {
    try {
      if (await _geofencing.hasBackgroundRegionCallback()) {
        return true;
      }
      final bool registered = await _geofencing
          .registerBackgroundRegionCallback(onWoosmapRegionEvent);
      debugPrint('registerBackgroundRegionCallback: $registered');
      return registered;
    } catch (e) {
      debugPrint('registerBackgroundRegionCallback error: $e');
      return false;
    }
  }

  /// Whether a background region callback is currently registered.
  Future<bool> hasBackgroundCallback() async {
    try {
      return await _geofencing.hasBackgroundRegionCallback();
    } catch (e) {
      debugPrint('hasBackgroundRegionCallback error: $e');
      return false;
    }
  }

  /// Stop tracking (e.g. when the user opts out).
  ///
  /// This also removes the background region callback: no region event is
  /// produced once tracking is stopped, so nothing is left to wake it.
  Future<void> stop() async {
    try {
      final String? result = await _geofencing.stopTracking();
      debugPrint('stopTracking: $result');
    } catch (e) {
      debugPrint('stopTracking error: $e');
    }
  }
}
