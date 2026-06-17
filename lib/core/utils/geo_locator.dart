import 'dart:convert';

import 'package:http/http.dart' as http;

/// An approximate location derived from the user's public IP.
class GeoPlace {
  final String city;
  final double? latitude;
  final double? longitude;

  const GeoPlace({required this.city, this.latitude, this.longitude});

  /// Caiyun-style `lng,lat` location string (2 decimals, as the weather API
  /// expects), or null if coordinates are absent.
  String? get lngLat => (latitude != null && longitude != null)
      ? '${longitude!.toStringAsFixed(2)},${latitude!.toStringAsFixed(2)}'
      : null;

  bool get hasCoordinates => latitude != null && longitude != null;
}

/// Resolves the user's approximate location via free, key-less HTTPS IP
/// geolocation services (best-effort, with fallbacks).
class GeoLocator {
  GeoLocator._();

  static GeoPlace? _cached;

  static Future<GeoPlace?> detect({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) return _cached;

    final place = await _tryIpWhoIs() ?? await _tryGeoJs();
    if (place != null) _cached = place;
    return place;
  }

  static Future<GeoPlace?> _tryIpWhoIs() async {
    try {
      final res = await http
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body);
      if (j is! Map || j['success'] != true) return null;
      return GeoPlace(
        city: '${j['city'] ?? ''}'.trim(),
        latitude: _toDouble(j['latitude']),
        longitude: _toDouble(j['longitude']),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<GeoPlace?> _tryGeoJs() async {
    try {
      final res = await http
          .get(Uri.parse('https://get.geojs.io/v1/ip/geo.json'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body);
      if (j is! Map) return null;
      return GeoPlace(
        city: '${j['city'] ?? ''}'.trim(),
        latitude: _toDouble(j['latitude']),
        longitude: _toDouble(j['longitude']),
      );
    } catch (_) {
      return null;
    }
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}
