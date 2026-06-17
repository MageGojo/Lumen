import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide user settings, persisted with [SharedPreferences].
///
/// Holds the Apizero API key (used by video parsing), the parse endpoint
/// (so the source can be swapped/extended), the preferred theme mode, and the
/// default download User-Agent + request headers (so sites that gate downloads
/// behind a specific UA / token header can be fetched).
class SettingsController extends ChangeNotifier {
  static const _kApiKey = 'apizero_api_key';
  static const _kParseBaseUrl = 'apizero_parse_base_url';
  static const _kThemeMode = 'app_theme_mode';
  static const _kBridgePort = 'bridge_port';
  static const _kDuplicateCheck = 'duplicate_check_enabled';
  static const _kUserAgent = 'download_user_agent';
  static const _kHeaders = 'download_headers';

  static const String defaultParseBaseUrl = 'https://v1.apizero.cn/api';
  static const int defaultBridgePort = 8787;

  /// A common desktop-Chrome UA, offered as a one-tap preset for sites that
  /// reject non-browser clients.
  static const String chromeUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  SharedPreferences? _prefs;

  String _apiKey = '';
  String _parseBaseUrl = defaultParseBaseUrl;
  ThemeMode _themeMode = ThemeMode.dark;
  int _bridgePort = defaultBridgePort;
  bool _duplicateCheckEnabled = true;
  String _userAgent = '';
  Map<String, String> _customHeaders = const {};

  String get apiKey => _apiKey;
  String get parseBaseUrl => _parseBaseUrl;
  ThemeMode get themeMode => _themeMode;
  int get bridgePort => _bridgePort;

  /// Whether to scan the destination directory for duplicates before a download
  /// starts (and prompt the user). On by default.
  bool get duplicateCheckEnabled => _duplicateCheckEnabled;

  /// Default User-Agent applied to every direct HTTP(S) download (empty = use
  /// the engine default). When set, downloads are routed through the aria2
  /// engine, which can carry a custom UA (the Surge CLI cannot).
  String get userAgent => _userAgent;

  /// Default extra request headers (e.g. `Cookie`, `Authorization`, `Referer`)
  /// applied to every direct HTTP(S) download.
  Map<String, String> get customHeaders => Map.unmodifiable(_customHeaders);

  /// The headers rendered as editable `Key: Value` lines for the settings UI.
  String get customHeadersText => headersToText(_customHeaders);

  bool get hasApiKey => _apiKey.trim().isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _apiKey = prefs.getString(_kApiKey) ?? '';
    _parseBaseUrl = prefs.getString(_kParseBaseUrl) ?? defaultParseBaseUrl;
    _themeMode = _themeModeFromName(prefs.getString(_kThemeMode));
    _bridgePort = prefs.getInt(_kBridgePort) ?? defaultBridgePort;
    _duplicateCheckEnabled = prefs.getBool(_kDuplicateCheck) ?? true;
    _userAgent = prefs.getString(_kUserAgent) ?? '';
    _customHeaders = _decodeHeaders(prefs.getString(_kHeaders));
    notifyListeners();
  }

  Future<void> setApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed == _apiKey) return;
    _apiKey = trimmed;
    notifyListeners();
    await _prefs?.setString(_kApiKey, trimmed);
  }

  Future<void> setParseBaseUrl(String value) async {
    final trimmed = value.trim();
    final next = trimmed.isEmpty ? defaultParseBaseUrl : trimmed;
    if (next == _parseBaseUrl) return;
    _parseBaseUrl = next;
    notifyListeners();
    await _prefs?.setString(_kParseBaseUrl, next);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs?.setString(_kThemeMode, mode.name);
  }

  Future<void> setBridgePort(int port) async {
    if (port < 1024 || port > 65535 || port == _bridgePort) return;
    _bridgePort = port;
    notifyListeners();
    await _prefs?.setInt(_kBridgePort, port);
  }

  Future<void> setDuplicateCheckEnabled(bool value) async {
    if (value == _duplicateCheckEnabled) return;
    _duplicateCheckEnabled = value;
    notifyListeners();
    await _prefs?.setBool(_kDuplicateCheck, value);
  }

  Future<void> setUserAgent(String value) async {
    final trimmed = value.trim();
    if (trimmed == _userAgent) return;
    _userAgent = trimmed;
    notifyListeners();
    await _prefs?.setString(_kUserAgent, trimmed);
  }

  /// Stores headers parsed from `Key: Value` lines (one per line). Blank lines
  /// and lines without a separator are ignored.
  Future<void> setCustomHeadersFromText(String text) async {
    final parsed = parseHeadersText(text);
    if (mapEquals(parsed, _customHeaders)) return;
    _customHeaders = parsed;
    notifyListeners();
    await _prefs?.setString(_kHeaders, jsonEncode(parsed));
  }

  // ---- Header (de)serialization helpers --------------------------------------

  static Map<String, String> parseHeadersText(String text) {
    final out = <String, String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.isEmpty) continue;
      out[key] = value;
    }
    return out;
  }

  static String headersToText(Map<String, String> headers) =>
      headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');

  static Map<String, String> _decodeHeaders(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry('$k', '$v'));
      }
    } catch (_) {
      // Corrupt value — fall back to none.
    }
    return const {};
  }

  static ThemeMode _themeModeFromName(String? name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }
}
