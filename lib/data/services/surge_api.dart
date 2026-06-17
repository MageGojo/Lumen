import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/download_task.dart';

class SurgeApiException implements Exception {
  final String message;
  const SurgeApiException(this.message);
  @override
  String toString() => message;
}

/// Read-only HTTP client for the Surge daemon API.
class SurgeApi {
  final http.Client _client;
  final String baseUrl;
  final String token;

  SurgeApi({required this.baseUrl, required this.token, http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _headers => {'Authorization': 'Bearer $token'};

  /// `GET /list` -> full task list with rich fields.
  Future<List<DownloadTask>> list() async {
    final res = await _client
        .get(Uri.parse('$baseUrl/list'), headers: _headers)
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      throw SurgeApiException('GET /list 返回 ${res.statusCode}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DownloadTask.fromJson)
        .toList(growable: false);
  }

  /// `GET /health` -> daemon liveness probe.
  Future<bool> health() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/health'), headers: _headers)
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.close();
}
