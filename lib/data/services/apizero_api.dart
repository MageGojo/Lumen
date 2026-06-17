import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiZeroException implements Exception {
  final String message;
  const ApiZeroException(this.message);

  @override
  String toString() => message;
}

/// Small HTTP client for the Apizero public API tools.
class ApiZeroApi {
  final http.Client _client;

  /// Mutable so the parse source can be reconfigured from Settings.
  String baseUrl;

  ApiZeroApi({http.Client? client, this.baseUrl = 'https://v1.apizero.cn/api'})
    : _client = client ?? http.Client();

  Future<Map<String, dynamic>> parseVideo({
    required String url,
    String? apiKey,
  }) {
    return _get(
      'video-parse',
      query: {'url': url},
      apiKey: apiKey,
      timeout: const Duration(seconds: 25),
    );
  }

  Future<Map<String, dynamic>> weather({
    String type = 'weather',
    String? city,
    String? location,
    bool alert = true,
    int days = 5,
    int hours = 24,
    String? apiKey,
  }) {
    return _get(
      'weather',
      query: {
        'type': type,
        'city': city,
        'location': location,
        'alert': alert ? 'true' : 'false',
        'days': '$days',
        'hours': '$hours',
      },
      apiKey: apiKey,
      timeout: const Duration(seconds: 15),
    );
  }

  Future<Map<String, dynamic>> hitokoto({
    String? category,
    int? minLength,
    int? maxLength,
    String? apiKey,
  }) {
    return _get(
      'hitokoto',
      query: {
        'c': category,
        'min_length': minLength?.toString(),
        'max_length': maxLength?.toString(),
      },
      apiKey: apiKey,
      timeout: const Duration(seconds: 10),
    );
  }

  Future<Map<String, dynamic>> _get(
    String endpoint, {
    required Map<String, String?> query,
    String? apiKey,
    required Duration timeout,
  }) async {
    final cleaned = <String, String>{};
    for (final entry in query.entries) {
      final value = entry.value?.trim();
      if (value != null && value.isNotEmpty) {
        cleaned[entry.key] = value;
      }
    }

    final key = apiKey?.trim();
    if (key != null && key.isNotEmpty) {
      cleaned['key'] = key;
    }

    final uri = Uri.parse(
      '$baseUrl/$endpoint',
    ).replace(queryParameters: cleaned);
    final headers = <String, String>{};
    if (key != null && key.isNotEmpty) {
      headers['X-API-Key'] = key;
    }

    final res = await _client.get(uri, headers: headers).timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiZeroException(
        'HTTP ${res.statusCode}: ${res.reasonPhrase ?? '请求失败'}',
      );
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiZeroException('接口返回格式不是 JSON 对象');
    }

    final code = decoded['code'];
    if (code is num && code != 0) {
      final msg = decoded['msg'] ?? decoded['message'] ?? '接口返回错误';
      throw ApiZeroException('$msg (code: $code)');
    }

    return decoded;
  }

  void dispose() => _client.close();
}
