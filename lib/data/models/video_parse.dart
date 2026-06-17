/// Typed model for the Apizero `video-parse` response.
///
/// Mirrors the documented payload shape:
/// `{ code, msg, data: { platform, type, title, video_url, cover_url,
///    audio_url, imagelist, source, stats, video_list } }`.
class VideoQuality {
  final String quality;
  final String url;
  final String size;
  final String resolution;

  const VideoQuality({
    required this.quality,
    required this.url,
    required this.size,
    required this.resolution,
  });

  factory VideoQuality.fromJson(Map<String, dynamic> json) {
    return VideoQuality(
      quality: _str(json['quality']),
      url: _str(json['url']),
      size: _str(json['size']),
      resolution: _str(json['resolution']),
    );
  }

  bool get hasUrl => url.isNotEmpty;
}

class VideoParseResult {
  final String platform;
  final String platformLabel;
  final String type;
  final String title;
  final String videoUrl;
  final String coverUrl;
  final String audioUrl;
  final List<String> imageList;
  final String authorName;
  final String authorAvatar;
  final String originalUrl;
  final List<VideoQuality> videoList;

  const VideoParseResult({
    required this.platform,
    required this.platformLabel,
    required this.type,
    required this.title,
    required this.videoUrl,
    required this.coverUrl,
    required this.audioUrl,
    required this.imageList,
    required this.authorName,
    required this.authorAvatar,
    required this.originalUrl,
    required this.videoList,
  });

  factory VideoParseResult.fromResponse(Map<String, dynamic> response) {
    final rawData = response['data'];
    final data = rawData is Map
        ? rawData.cast<String, dynamic>()
        : response;
    final source = _map(data['source']);
    final stats = _map(data['stats']);

    final videoList = <VideoQuality>[];
    final rawList = data['video_list'];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          videoList.add(VideoQuality.fromJson(item.cast<String, dynamic>()));
        }
      }
    }

    final images = <String>[];
    final rawImages = data['imagelist'];
    if (rawImages is List) {
      for (final item in rawImages) {
        final s = _str(item);
        if (s.isNotEmpty) images.add(s);
      }
    }

    return VideoParseResult(
      platform: _str(data['platform']),
      platformLabel: _firstNonEmpty([
        _str(source['platform_label']),
        _str(data['platform']),
      ]),
      type: _str(data['type']),
      title: _str(data['title']),
      videoUrl: _str(data['video_url']),
      coverUrl: _str(data['cover_url']),
      audioUrl: _str(data['audio_url']),
      imageList: images,
      authorName: _firstNonEmpty([
        _str(source['author_name']),
        _str(stats['author_name']),
      ]),
      authorAvatar: _firstNonEmpty([
        _str(stats['author_avatar']),
        _str(source['author_avatar']),
      ]),
      originalUrl: _str(source['original_url']),
      videoList: videoList,
    );
  }

  bool get isImageText =>
      imageList.isNotEmpty && videoList.isEmpty && videoUrl.isEmpty;

  bool get hasDownloadable =>
      videoList.any((q) => q.hasUrl) ||
      videoUrl.isNotEmpty ||
      imageList.isNotEmpty;

  /// Preferred single URL when no explicit quality is chosen.
  String get bestVideoUrl {
    if (videoList.isNotEmpty) {
      final withUrl = videoList.firstWhere(
        (q) => q.hasUrl,
        orElse: () => videoList.first,
      );
      if (withUrl.hasUrl) return withUrl.url;
    }
    return videoUrl;
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

String _str(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  return '$value';
}

String _firstNonEmpty(List<String> values) {
  for (final v in values) {
    if (v.trim().isNotEmpty) return v;
  }
  return '';
}
