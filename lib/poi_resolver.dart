import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geofencing_flutter_plugin/geofencing_flutter_plugin.dart';

/// Base URL of the Woosmap Store API "get asset from id" endpoint.
///
/// See https://developers.woosmap.com/api-reference/data-api/get-stores-storeid/
const String kWoosmapStoreApiBase = 'https://api.woosmap.com/stores';

/// Normalized POI attributes merged into the back-office payload.
///
/// The keys are the same ones the previous native receivers sent, so the
/// back-office contract is unchanged.
typedef PoiFields = Map<String, Object?>;

/// Splits the comma-separated `tags`/`types` the plugin returns into a list, so
/// both sources produce the same shape.
List<String>? _splitCsv(String? value) {
  if (value == null || value.isEmpty) return null;
  return value
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();
}

List<String>? _asStringList(Object? value) {
  if (value is List) {
    return value.map((Object? e) => '$e').toList();
  }
  return _splitCsv(value as String?);
}

/// Drops null entries so the payload never carries empty POI keys.
PoiFields _compact(PoiFields fields) {
  fields.removeWhere((String _, Object? value) => value == null);
  return fields;
}

/// Flattens a [Poi] returned by the plugin's local database.
PoiFields poiFieldsFromPlugin(Poi poi) {
  return _compact(<String, Object?>{
    'idStore': poi.idstore,
    'name': poi.name,
    'city': poi.city,
    'zipCode': poi.zipcode,
    'countryCode': poi.countrycode,
    'address': poi.address,
    'tags': _splitCsv(poi.tags),
    'types': _splitCsv(poi.types),
    'distance': poi.distance,
  });
}

/// Flattens a GeoJSON `Feature` returned by the Woosmap Store API.
///
/// The response nests the postal fields under `address` and names the id
/// `store_id`, so this maps them onto the same keys as [poiFieldsFromPlugin].
PoiFields poiFieldsFromStoreFeature(Map<String, dynamic> feature) {
  final Map<String, dynamic> props =
      (feature['properties'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final Map<String, dynamic> address =
      (props['address'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final Object? lines = address['lines'];

  return _compact(<String, Object?>{
    'idStore': props['store_id'],
    'name': props['name'],
    'city': address['city'],
    'zipCode': address['zipcode'],
    'countryCode': address['country_code'],
    'address': lines is List ? lines.join(', ') : lines,
    'tags': _asStringList(props['tags']),
    'types': _asStringList(props['types']),
    'distance': props['distance'],
  });
}

/// Reads a single store from the Woosmap Store API over plain `dart:io`.
///
/// No Flutter plugin is involved, so this works in the background isolate on
/// both platforms — including when the application has been terminated.
class WoosmapStoreApi {
  /// Creates a client. [httpClientFactory] is only meant to be overridden by
  /// tests.
  WoosmapStoreApi({
    required this.apiKey,
    this.baseUrl = kWoosmapStoreApiBase,
    this.timeout = const Duration(seconds: 15),
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Woosmap private API key, sent in the `X-Api-Key` header.
  ///
  /// The key deliberately does not go in the query string: URLs end up in
  /// server logs and crash reports.
  final String apiKey;

  /// Base URL of the store endpoint, without a trailing slash.
  final String baseUrl;

  /// Budget for the whole request; the callback only gets a short window.
  final Duration timeout;

  final HttpClient Function() _httpClientFactory;

  /// Fetches the store identified by [storeId], or null when it cannot be
  /// read. Never throws.
  Future<PoiFields?> fetchPoi(String storeId) async {
    HttpClient? client;
    try {
      client = _httpClientFactory();
      client.connectionTimeout = timeout;
      final Uri uri = Uri.parse('$baseUrl/${Uri.encodeComponent(storeId)}/');
      final HttpClientRequest request = await client.getUrl(uri);
      request.headers.set('X-Api-Key', apiKey);

      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        debugPrint('Woosmap: store API responded ${response.statusCode}');
        return null;
      }
      return poiFieldsFromStoreFeature(
          jsonDecode(body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Woosmap: store API error: $e');
      return null;
    } finally {
      client?.close();
    }
  }
}

/// Resolves the POI behind a region identifier, preferring the local database
/// when it is reachable and falling back to the Store API.
///
/// The plugin's `getPois` is a method-channel call, so it only works where the
/// background isolate has the plugins registered — that is **iOS only**, and
/// only once `AppDelegate` calls
/// `GeofencingFlutterPlugin.setPluginRegistrantCallback`. The Android
/// background engine registers no plugins and has no Activity, so the network
/// path is the only one available there.
class PoiResolver {
  /// Creates a resolver. [isIOS] and [pluginLookup] are only meant to be
  /// overridden by tests.
  PoiResolver({
    required WoosmapStoreApi storeApi,
    bool? isIOS,
    Future<List<Poi>?> Function(String storeId)? pluginLookup,
  })  : _storeApi = storeApi,
        _isIOS = isIOS ?? Platform.isIOS,
        _pluginLookup = pluginLookup ?? _defaultPluginLookup;

  static Future<List<Poi>?> _defaultPluginLookup(String storeId) =>
      GeofencingFlutterPlugin().getPois(storeId);

  final WoosmapStoreApi _storeApi;
  final bool _isIOS;
  final Future<List<Poi>?> Function(String storeId) _pluginLookup;

  /// Returns the POI attributes for [storeId], or null when neither source can
  /// supply them. Never throws.
  Future<PoiFields?> resolve(String storeId) async {
    if (storeId.isEmpty) return null;
    final PoiFields? local = await _fromPlugin(storeId);
    if (local != null) return local;
    return _storeApi.fetchPoi(storeId);
  }

  /// Reads the POI from the plugin's local database. Returns null on Android,
  /// where the background isolate has no plugin channels.
  Future<PoiFields?> _fromPlugin(String storeId) async {
    if (!_isIOS) return null;
    try {
      final List<Poi>? pois = await _pluginLookup(storeId);
      if (pois == null || pois.isEmpty) return null;
      return poiFieldsFromPlugin(pois.first);
    } catch (e) {
      // MissingPluginException when the registrant callback was not set.
      debugPrint('Woosmap: local POI lookup unavailable: $e');
      return null;
    }
  }
}
