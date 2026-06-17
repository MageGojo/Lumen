/// Lifecycle states reported by the Surge daemon for a download.
enum DownloadStatus { queued, downloading, paused, completed, error, unknown }

DownloadStatus _statusFromString(String? raw) {
  switch (raw?.toLowerCase().trim()) {
    case 'queued':
    case 'pending':
    case 'waiting':
    case 'starting':
      return DownloadStatus.queued;
    case 'downloading':
    case 'active':
    case 'running':
    case 'in_progress':
      return DownloadStatus.downloading;
    case 'paused':
    case 'stopped':
      return DownloadStatus.paused;
    case 'completed':
    case 'complete':
    case 'done':
    case 'finished':
      return DownloadStatus.completed;
    case 'error':
    case 'failed':
    case 'failure':
      return DownloadStatus.error;
    default:
      return DownloadStatus.unknown;
  }
}

/// Immutable view of one download, parsed from `GET /list`.
class DownloadTask {
  final String id;
  final String url;
  final String filename;
  final String destPath;
  final int totalSize;
  final int downloaded;
  final double progress; // 0 - 100
  final double speedMbps; // current speed, MB/s
  final DownloadStatus status;
  final int etaSeconds;
  final int connections;
  final int timeTakenMs;
  final double avgSpeedBps;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.filename,
    required this.destPath,
    required this.totalSize,
    required this.downloaded,
    required this.progress,
    required this.speedMbps,
    required this.status,
    required this.etaSeconds,
    required this.connections,
    required this.timeTakenMs,
    required this.avgSpeedBps,
  });

  double get speedBytesPerSec => speedMbps * 1024 * 1024;

  double get fraction => (progress.clamp(0, 100)) / 100.0;

  bool get isActive =>
      status == DownloadStatus.downloading ||
      status == DownloadStatus.queued ||
      status == DownloadStatus.paused;

  String get extension {
    final name = filename;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    num asNum(dynamic v) =>
        v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
    final url = '${json['url'] ?? ''}';
    final filename = '${json['filename'] ?? ''}'.isNotEmpty
        ? '${json['filename']}'
        : (url.isNotEmpty ? Uri.tryParse(url)?.pathSegments.last ?? url : '未命名');
    return DownloadTask(
      id: '${json['id'] ?? ''}',
      url: url,
      filename: filename,
      destPath: '${json['dest_path'] ?? ''}',
      totalSize: asNum(json['total_size']).toInt(),
      downloaded: asNum(json['downloaded']).toInt(),
      progress: asNum(json['progress']).toDouble(),
      speedMbps: asNum(json['speed']).toDouble(),
      status: _statusFromString(json['status'] as String?),
      etaSeconds: asNum(json['eta']).toInt(),
      connections: asNum(json['connections']).toInt(),
      timeTakenMs: asNum(json['time_taken']).toInt(),
      avgSpeedBps: asNum(json['avg_speed']).toDouble(),
    );
  }
}
