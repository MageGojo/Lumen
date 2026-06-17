import 'dart:convert';

import 'package:http/http.dart' as http;

/// Raised when an aria2 JSON-RPC call fails (transport or protocol error).
class Aria2RpcException implements Exception {
  final String message;
  const Aria2RpcException(this.message);
  @override
  String toString() => message;
}

/// Minimal JSON-RPC 2.0 client for the aria2 daemon (the torrent engine).
///
/// aria2 exposes every operation over `POST /jsonrpc`; the secret token is
/// passed as the first positional param in the form `token:<secret>`.
class Aria2Rpc {
  final String endpoint;
  final String secret;
  final http.Client _client;

  Aria2Rpc({
    required int port,
    required this.secret,
    http.Client? client,
  })  : endpoint = 'http://127.0.0.1:$port/jsonrpc',
        _client = client ?? http.Client();

  Future<dynamic> call(
    String method, [
    List<dynamic> params = const [],
  ]) async {
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': 'lumen',
      'method': method,
      'params': ['token:$secret', ...params],
    });

    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      throw Aria2RpcException('aria2 RPC 连接失败:$e');
    }

    if (res.statusCode != 200) {
      throw Aria2RpcException('aria2 RPC 返回 ${res.statusCode}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded['error'] != null) {
      final err = decoded['error'];
      final msg = err is Map ? err['message'] : err;
      throw Aria2RpcException('$msg');
    }
    return decoded is Map ? decoded['result'] : null;
  }

  void dispose() => _client.close();
}
