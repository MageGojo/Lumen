import 'package:flutter/foundation.dart';

import '../data/models/video_parse.dart';
import '../data/services/apizero_api.dart';

enum ApiToolKind { videoParse, weather, hitokoto }

class ApiToolsController extends ChangeNotifier {
  final ApiZeroApi _api;

  ApiToolsController({ApiZeroApi? api}) : _api = api ?? ApiZeroApi();

  ApiToolKind? runningTool;
  String apiKey = '';

  /// Shared error for weather / hitokoto cards.
  String? errorMessage;

  VideoParseResult? videoResult;
  String? videoSourceUrl;
  String? videoError;

  Map<String, dynamic>? weatherResult;
  Map<String, dynamic>? hitokotoResult;

  bool get busy => runningTool != null;
  bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// Whether the video parse panel should be shown at all.
  bool get hasVideoActivity =>
      runningTool == ApiToolKind.videoParse ||
      videoResult != null ||
      videoError != null;

  bool isBusy(ApiToolKind kind) => runningTool == kind;

  void setApiKey(String value) {
    apiKey = value.trim();
    notifyListeners();
  }

  void setBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) _api.baseUrl = trimmed;
  }

  /// Sends a social/share link to Apizero and stores the typed result.
  Future<void> parseShareLink(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      videoError = '请先粘贴视频 / 图文分享链接';
      notifyListeners();
      return;
    }
    if (!hasApiKey) {
      videoError = '视频解析需要先在设置里填写 Apizero API Key';
      notifyListeners();
      return;
    }
    if (busy) return;

    videoSourceUrl = trimmed;
    videoError = null;
    videoResult = null;
    runningTool = ApiToolKind.videoParse;
    notifyListeners();
    try {
      final raw = await _api.parseVideo(url: trimmed, apiKey: apiKey);
      videoResult = VideoParseResult.fromResponse(raw);
      if (!videoResult!.hasDownloadable) {
        videoError = '未解析到可下载的资源,请确认链接是否有效';
      }
    } catch (e) {
      videoError = '$e';
    } finally {
      runningTool = null;
      notifyListeners();
    }
  }

  void clearVideo() {
    videoResult = null;
    videoSourceUrl = null;
    videoError = null;
    notifyListeners();
  }

  Future<void> fetchWeather({
    required String type,
    required String city,
    required String location,
    required bool alert,
    required int days,
    required int hours,
  }) async {
    if (city.trim().isEmpty && location.trim().isEmpty) {
      _setError('城市和经纬度至少填写一个');
      return;
    }
    await _run(ApiToolKind.weather, () async {
      weatherResult = await _api.weather(
        type: type,
        city: city,
        location: location,
        alert: alert,
        days: days.clamp(1, 15),
        hours: hours.clamp(1, 360),
        apiKey: apiKey,
      );
    });
  }

  Future<void> fetchHitokoto({
    String? category,
    int? minLength,
    int? maxLength,
  }) async {
    if (minLength != null && maxLength != null && minLength > maxLength) {
      _setError('最小长度不能大于最大长度');
      return;
    }
    await _run(ApiToolKind.hitokoto, () async {
      hitokotoResult = await _api.hitokoto(
        category: category,
        minLength: minLength,
        maxLength: maxLength,
        apiKey: apiKey,
      );
    });
  }

  Future<void> _run(ApiToolKind kind, Future<void> Function() action) async {
    if (busy) return;
    runningTool = kind;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      errorMessage = '$e';
    } finally {
      runningTool = null;
      notifyListeners();
    }
  }

  void _setError(String message) {
    errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}
