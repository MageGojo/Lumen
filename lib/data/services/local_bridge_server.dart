import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Result returned to the browser extension after handling a link.
class BridgeResult {
  final bool ok;
  final String message;
  const BridgeResult(this.ok, this.message);
}

typedef BridgeAddHandler = Future<BridgeResult> Function(
  String url, {
  String? referer,
  String? title,
  String? userAgent,
  Map<String, String>? headers,
});

/// A tiny loopback-only HTTP server that lets a sideloaded browser
/// extension hand off sniffed media links to the app.
///
/// Endpoints:
///   GET  /ping  -> { app: "lumen", ok: true }
///   POST /add   -> { url } => { ok, message }
class LocalBridgeServer {
  final int port;
  final BridgeAddHandler onAdd;

  HttpServer? _server;
  bool get isRunning => _server != null;

  LocalBridgeServer({required this.port, required this.onAdd});

  Future<bool> start() async {
    if (_server != null) return true;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server!.listen(_handle, onError: (_) {});
      return true;
    } catch (_) {
      // Port busy or blocked — the app still works, just without the bridge.
      _server = null;
      return false;
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', 'Content-Type')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');

    try {
      if (req.method == 'OPTIONS') {
        res.statusCode = HttpStatus.noContent;
        await res.close();
        return;
      }

      final path = req.uri.path;

      if (path == '/ping') {
        await _writeJson(res, {'app': 'lumen', 'ok': true});
        return;
      }

      if (path == '/add' && req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        String url = '';
        String? referer;
        String? title;
        String? userAgent;
        Map<String, String>? headers;
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map && decoded['url'] != null) {
            url = decoded['url'].toString().trim();
            referer = decoded['referer']?.toString();
            title = decoded['title']?.toString();
            userAgent = decoded['userAgent']?.toString();
            final h = decoded['headers'];
            if (h is Map) {
              headers = h.map((k, v) => MapEntry('$k', '$v'));
            }
          }
        } catch (_) {
          url = '';
        }
        if (url.isEmpty) {
          await _writeJson(
            res,
            {'ok': false, 'message': '缺少 url 参数'},
            code: HttpStatus.badRequest,
          );
          return;
        }
        final result = await onAdd(
          url,
          referer: referer,
          title: title,
          userAgent: userAgent,
          headers: headers,
        );
        await _writeJson(res, {'ok': result.ok, 'message': result.message});
        return;
      }

      res.statusCode = HttpStatus.notFound;
      await res.close();
    } catch (_) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _writeJson(
    HttpResponse res,
    Map<String, dynamic> body, {
    int code = HttpStatus.ok,
  }) async {
    res
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await res.close();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
