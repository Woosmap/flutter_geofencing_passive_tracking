import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geofencing_flutter_plugin/geofencing_flutter_plugin.dart';

/// Back-office endpoint that receives the geofence events.
// TODO: point this at the customer's back-office.
const String kBackOfficeUrl =
    'https://api.customer-backoffice.example.com/geofence-events';

/// Bearer token used to authenticate against [kBackOfficeUrl].
///
/// For production, inject it at runtime (secure storage, or a build-time
/// environment variable read with `String.fromEnvironment`) instead of
/// hardcoding it here.
// TODO: point this at the customer's back-office.
const String kBackOfficeApiKey = 'CUSTOMER_API_KEY';

/// Builds the JSON body sent to the back-office for [region].
///
/// Field names follow the Woosmap connector event spec.
Map<String, Object?> regionEventPayload(Region region) {
  return <String, Object?>{
    'date': region.date,
    'eventName': region.eventName,
    'id': region.identifier,
    'latitude': region.latitude,
    'longitude': region.longitude,
    'radius': region.radius,
    'didEnter': region.didEnter,
    'spentTime': region.spentTime,
    'fromPositionDetection': region.fromPositionDetection,
  };
}

/// POSTs geofence region events to the customer's back-office.
///
/// Uses `dart:io` only: the instance created by [onWoosmapRegionEvent] runs in
/// a background isolate where no Flutter plugin is registered, so no plugin
/// channel may be called from here.
class BackOfficeForwarder {
  /// Creates a forwarder. [httpClientFactory] is only meant to be overridden
  /// by tests.
  BackOfficeForwarder({
    this.url = kBackOfficeUrl,
    this.apiKey = kBackOfficeApiKey,
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Endpoint the events are POSTed to.
  final String url;

  /// Bearer token sent in the `Authorization` header.
  final String apiKey;

  final HttpClient Function() _httpClientFactory;

  /// Sends [region] to [url]. Never throws: a geofence event must not crash
  /// the background isolate.
  Future<void> send(Region region) async {
    final HttpClient client = _httpClientFactory();
    try {
      client.connectionTimeout = const Duration(seconds: 30);
      final HttpClientRequest request = await client.postUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.write(jsonEncode(regionEventPayload(region)));

      final HttpClientResponse response = await request.close();
      await response.drain<void>();
      debugPrint('Woosmap: back-office responded ${response.statusCode}');
    } catch (e) {
      debugPrint('Woosmap: back-office POST error: $e');
    } finally {
      client.close();
    }
  }
}

/// Handles a geofence region event and forwards it to the back-office.
///
/// Registered with `registerBackgroundRegionCallback`, so the plugin wakes it
/// in a **background isolate** — with no widget tree and no other plugin
/// available — whenever a region event cannot be delivered on the region
/// stream, including after the application has been terminated.
///
/// It must stay a top-level function annotated with `@pragma('vm:entry-point')`
/// so the Dart VM can resolve it from that isolate.
@pragma('vm:entry-point')
Future<void> onWoosmapRegionEvent(Region region) async {
  debugPrint(
      'Woosmap: ${region.eventName} on ${region.identifier} '
      '(didEnter=${region.didEnter})');
  await BackOfficeForwarder().send(region);
}
