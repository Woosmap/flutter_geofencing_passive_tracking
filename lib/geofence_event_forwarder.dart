import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geofencing_flutter_plugin/geofencing_flutter_plugin.dart';

import 'geofencing_service.dart' show kWoosmapPrivateApiKey;
import 'poi_resolver.dart';

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
/// Field names follow the Woosmap connector event spec. [poi] holds the
/// attributes resolved by [PoiResolver]; they are merged in at the top level
/// and omitted entirely for a custom (non-POI) region.
Map<String, Object?> regionEventPayload(Region region, {PoiFields? poi}) {
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
    if (poi != null) ...poi,
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

  /// Sends [region] to [url], enriched with [poi] when it could be resolved.
  /// Never throws: a geofence event must not crash the background isolate.
  Future<void> send(Region region, {PoiFields? poi}) async {
    HttpClient? client;
    try {
      client = _httpClientFactory();
      client.connectionTimeout = const Duration(seconds: 30);
      final HttpClientRequest request = await client.postUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.write(jsonEncode(regionEventPayload(region, poi: poi)));

      final HttpClientResponse response = await request.close();
      await response.drain<void>();
      debugPrint('Woosmap: back-office responded ${response.statusCode}');
    } catch (e) {
      debugPrint('Woosmap: back-office POST error: $e');
    } finally {
      client?.close();
    }
  }
}

/// Handles a geofence region event and forwards it to the back-office.
///
/// Registered with `registerBackgroundRegionCallback`, so the plugin wakes it
/// in a **background isolate** — with no widget tree — whenever a region event
/// cannot be delivered on the region stream, including after the application
/// has been terminated.
///
/// The POI behind [Region.identifier] is looked up first (see [PoiResolver])
/// and merged into the payload; a failed lookup only costs the extra fields,
/// the event is still forwarded.
///
/// It must stay a top-level function annotated with `@pragma('vm:entry-point')`
/// so the Dart VM can resolve it from that isolate.
@pragma('vm:entry-point')
Future<void> onWoosmapRegionEvent(Region region) async {
  debugPrint(
      'Woosmap: ${region.eventName} on ${region.identifier} '
      '(didEnter=${region.didEnter})');

  final PoiResolver resolver = PoiResolver(
    storeApi: WoosmapStoreApi(apiKey: kWoosmapPrivateApiKey),
  );
  final PoiFields? poi = await resolver.resolve(region.identifier);
  if (poi != null) {
    debugPrint('Woosmap: resolved POI ${poi['name'] ?? poi['idStore']}');
  }

  await BackOfficeForwarder().send(region, poi: poi);
}
