import 'dart:io';

import '../../core/utils/native_binaries.dart';
import '../models/download_task.dart';
import 'aria2_rpc.dart';

/// Thrown when the `aria2c` binary cannot be located on the system.
class Aria2NotInstalled implements Exception {
  const Aria2NotInstalled();
  @override
  String toString() => 'aria2 未安装';
}

/// The BitTorrent / magnet engine, layered alongside Surge.
///
/// Surge is HTTP-only, so magnet + `.torrent` links are handled by a managed
/// `aria2c` daemon spoken to over JSON-RPC. A fixed loopback port + secret let
/// us transparently re-attach to an instance left running by a previous launch
/// (so in-flight torrents survive app restarts), and lazily spawn one on the
/// first torrent the user adds.
class Aria2Service {
  static const int _port = 6810;
  static const String _secret = 'lumen-local';

  static const List<String> _candidates = [
    '/opt/homebrew/bin/aria2c',
    '/usr/local/bin/aria2c',
    '/usr/bin/aria2c',
  ];

  /// Compact field set requested from aria2 to keep status payloads small.
  static const List<String> _keys = [
    'gid',
    'status',
    'totalLength',
    'completedLength',
    'downloadSpeed',
    'connections',
    'dir',
    'files',
    'bittorrent',
    'errorMessage',
    'following',
    'followedBy',
    'numSeeders',
  ];

  Aria2Rpc? _rpc;
  String? _binary;

  bool get ready => _rpc != null;

  // ---- Lifecycle -------------------------------------------------------------

  Future<String?> _resolveBinary() async {
    if (_binary != null) return _binary;

    final bundled = NativeBinaries.aria2cPath;
    if (bundled != null && await File(bundled).exists()) {
      _binary = bundled;
      return bundled;
    }

    for (final path in _candidates) {
      if (await File(path).exists()) {
        _binary = path;
        return path;
      }
    }
    try {
      final result = await Process.run('/bin/zsh', ['-lc', 'command -v aria2c'])
          .timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final path = '${result.stdout}'.trim().split('\n').first.trim();
        if (path.isNotEmpty && await File(path).exists()) {
          _binary = path;
          return path;
        }
      }
    } catch (_) {
      // ignore and report as not found
    }
    return null;
  }

  Future<bool> _ping() async {
    final rpc = _rpc;
    if (rpc == null) return false;
    try {
      await rpc.call('aria2.getVersion');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Re-attach to an already-running daemon without spawning a new one.
  Future<bool> attach() async {
    _rpc ??= Aria2Rpc(port: _port, secret: _secret);
    if (await _ping()) return true;
    _rpc?.dispose();
    _rpc = null;
    return false;
  }

  /// Ensures a daemon is reachable, spawning one if necessary.
  Future<void> ensureRunning({String? defaultDir}) async {
    _rpc ??= Aria2Rpc(port: _port, secret: _secret);
    if (await _ping()) return;

    final binary = await _resolveBinary();
    if (binary == null) throw const Aria2NotInstalled();

    final home = Platform.environment['HOME'];
    final dir = (defaultDir != null && defaultDir.trim().isNotEmpty)
        ? defaultDir.trim()
        : (home != null ? '$home/Downloads' : '.');

    await Process.start(
      binary,
      [
        '--enable-rpc=true',
        '--rpc-listen-all=false',
        '--rpc-listen-port=$_port',
        '--rpc-secret=$_secret',
        '--rpc-allow-origin-all=true',
        '--continue=true',
        '--dir=$dir',
        '--seed-time=0',
        '--bt-save-metadata=true',
        '--follow-torrent=true',
        '--max-concurrent-downloads=5',
        '--summary-interval=0',
        '--quiet=true',
        '--enable-dht=true',
        '--bt-enable-lpd=true',
      ],
      mode: ProcessStartMode.detached,
    );

    for (var attempt = 0; attempt < 24; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (await _ping()) return;
    }
    throw const Aria2RpcException('aria2 守护进程启动超时');
  }

  // ---- Operations ------------------------------------------------------------

  /// A desktop-Chrome UA used as a fallback when a [referer] is supplied but the
  /// caller didn't pass an explicit [userAgent]; many CDNs reject non-browsers.
  static const String _fallbackUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  /// Queues a URI (magnet/torrent, or an HTTP link that needs a [referer],
  /// custom [userAgent] or extra [headers]); returns the gid.
  ///
  /// [out] forces the output filename (used to keep a renamed copy when a
  /// duplicate is detected); Surge can't do this, but aria2 can via `out`.
  /// [userAgent] / [headers] let downloads carry a custom UA + request headers
  /// (e.g. `Cookie`, `Authorization`) for sites that gate downloads behind them.
  Future<String> add(
    String uri, {
    String? dir,
    String? referer,
    String? out,
    String? userAgent,
    Map<String, String>? headers,
  }) async {
    final rpc = _rpc;
    if (rpc == null) throw const Aria2RpcException('aria2 守护进程尚未就绪');
    final options = <String, dynamic>{};
    if (dir != null && dir.trim().isNotEmpty) options['dir'] = dir.trim();
    if (out != null && out.trim().isNotEmpty) options['out'] = out.trim();

    final hasReferer = referer != null && referer.trim().isNotEmpty;
    if (hasReferer) options['referer'] = referer.trim();

    final ua = userAgent?.trim() ?? '';
    if (ua.isNotEmpty) {
      options['user-agent'] = ua;
    } else if (hasReferer) {
      // Referer-gated CDNs almost always also expect a browser UA.
      options['user-agent'] = _fallbackUserAgent;
    }

    if (headers != null && headers.isNotEmpty) {
      // aria2 takes repeated headers as a list of raw "Name: Value" strings.
      options['header'] = headers.entries
          .where((e) => e.key.trim().isNotEmpty)
          .map((e) => '${e.key.trim()}: ${e.value}')
          .toList();
    }

    final gid = await rpc.call('aria2.addUri', [
      [uri],
      options,
    ]);
    return '$gid';
  }

  Future<List<DownloadTask>> tasks() async {
    final rpc = _rpc;
    if (rpc == null) return const [];
    final active = await rpc.call('aria2.tellActive', [_keys]);
    final waiting = await rpc.call('aria2.tellWaiting', [0, 500, _keys]);
    final stopped = await rpc.call('aria2.tellStopped', [0, 500, _keys]);

    final entries = <Map>[
      ...(active is List ? active : const []),
      ...(waiting is List ? waiting : const []),
      ...(stopped is List ? stopped : const []),
    ].whereType<Map>();

    final out = <DownloadTask>[];
    for (final entry in entries) {
      // A magnet first downloads metadata, which then spawns the real task via
      // `followedBy`. Skip those placeholders so the UI shows one clean item.
      final followedBy = entry['followedBy'];
      if (followedBy is List && followedBy.isNotEmpty) continue;
      out.add(_map(entry));
    }
    return out;
  }

  Future<void> pause(String gid) => _rpc!.call('aria2.pause', [gid]);

  Future<void> resume(String gid) => _rpc!.call('aria2.unpause', [gid]);

  Future<void> remove(String gid, {bool purge = false}) async {
    final rpc = _rpc;
    if (rpc == null) return;

    String? target;
    if (purge) {
      try {
        final status = await rpc.call('aria2.tellStatus', [
          gid,
          ['files', 'dir', 'bittorrent'],
        ]);
        if (status is Map) target = _purgeTarget(status);
      } catch (_) {
        // best-effort; we may simply skip on-disk deletion
      }
    }

    // `remove` only works on active/waiting/paused; completed/errored items
    // need `removeDownloadResult`. Try both so either state is cleared.
    try {
      await rpc.call('aria2.remove', [gid]);
    } catch (_) {}
    try {
      await rpc.call('aria2.removeDownloadResult', [gid]);
    } catch (_) {}

    if (purge && target != null && target.isNotEmpty) {
      await _deletePath(target);
    }
  }

  Future<void> pauseAll() => _rpc!.call('aria2.pauseAll');

  Future<void> resumeAll() => _rpc!.call('aria2.unpauseAll');

  Future<void> clean() => _rpc!.call('aria2.purgeDownloadResult');

  Future<void> setLimit(String speed) => _rpc!.call('aria2.changeGlobalOption', [
        {'max-overall-download-limit': _toAria2Speed(speed)},
      ]);

  void dispose() => _rpc?.dispose();

  // ---- Mapping helpers -------------------------------------------------------

  DownloadTask _map(Map m) {
    int asInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

    final gid = '${m['gid'] ?? ''}';
    final total = asInt(m['totalLength']);
    final done = asInt(m['completedLength']);
    final speed = asInt(m['downloadSpeed']);
    final dir = '${m['dir'] ?? ''}';
    final files = m['files'] is List ? m['files'] as List : const [];
    final bt = m['bittorrent'];

    var name = '';
    if (bt is Map && bt['info'] is Map) {
      name = '${(bt['info'] as Map)['name'] ?? ''}';
    }
    var dest = '';
    if (files.isNotEmpty && files.first is Map) {
      final path = '${(files.first as Map)['path'] ?? ''}';
      if (path.isNotEmpty) {
        dest = path;
        if (name.isEmpty) name = path.split('/').last;
      }
    }

    // Magnet metadata phase: no real name yet (aria2 uses a "[METADATA]" stub).
    final fetchingMeta = name.isEmpty || name.startsWith('[METADATA]');
    if (fetchingMeta) {
      name = '磁力链接解析中…';
      dest = dir;
    } else if (dest.isEmpty) {
      dest = dir;
    }

    final progress = total > 0 ? (done / total) * 100.0 : 0.0;
    final eta = (speed > 0 && total > done) ? ((total - done) / speed).round() : 0;

    return DownloadTask(
      id: 'aria2:$gid',
      url: '',
      filename: name,
      destPath: dest,
      totalSize: total,
      downloaded: done,
      progress: progress,
      speedMbps: speed / (1024 * 1024),
      status: _statusFromAria2('${m['status'] ?? ''}'),
      etaSeconds: eta,
      connections: asInt(m['connections']),
      timeTakenMs: 0,
      avgSpeedBps: speed.toDouble(),
    );
  }

  DownloadStatus _statusFromAria2(String raw) {
    switch (raw) {
      case 'active':
        return DownloadStatus.downloading;
      case 'waiting':
        return DownloadStatus.queued;
      case 'paused':
        return DownloadStatus.paused;
      case 'complete':
        return DownloadStatus.completed;
      case 'error':
      case 'removed':
        return DownloadStatus.error;
      default:
        return DownloadStatus.unknown;
    }
  }

  String? _purgeTarget(Map status) {
    final dir = '${status['dir'] ?? ''}';
    final bt = status['bittorrent'];
    if (bt is Map && bt['info'] is Map) {
      final name = '${(bt['info'] as Map)['name'] ?? ''}';
      if (name.isNotEmpty && dir.isNotEmpty) return '$dir/$name';
    }
    final files = status['files'];
    if (files is List && files.isNotEmpty && files.first is Map) {
      final path = '${(files.first as Map)['path'] ?? ''}';
      if (path.isNotEmpty) return path;
    }
    return null;
  }

  Future<void> _deletePath(String path) async {
    try {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await File(path).delete();
      }
    } catch (_) {
      // best-effort
    }
  }

  /// Surge speed strings (e.g. `5MB/s`, `500KB/s`, `0`) -> aria2 form (`5M`).
  String _toAria2Speed(String speed) {
    var v = speed.trim().toUpperCase().replaceAll(' ', '').replaceAll('/S', '');
    if (v.isEmpty) return '0';
    v = v
        .replaceAll('MB', 'M')
        .replaceAll('KB', 'K')
        .replaceAll('GB', 'G')
        .replaceAll('B', '');
    return v.isEmpty ? '0' : v;
  }
}
