import '../../core/utils/link_classifier.dart';
import '../models/download_task.dart';
import '../services/aria2_service.dart';
import '../services/surge_api.dart';
import '../services/surge_cli.dart';
import '../services/surge_daemon.dart';

/// Aggregates the two download engines behind a single surface:
///   * Surge (HTTP multi-connection) — the default for normal links;
///   * aria2 (BitTorrent) — for `magnet:` / `.torrent` links.
///
/// Adds are routed by link type; per-task mutations are routed by an `aria2:`
/// id prefix. The task list merges both engines so the UI stays unified.
class DownloadRepository {
  final SurgeDaemon _daemon = SurgeDaemon();
  final Aria2Service _aria2 = Aria2Service();
  SurgeApi? _api;
  SurgeCli? _cli;

  static const String _aria2Prefix = 'aria2:';

  DaemonInfo? get info => _daemon.info;

  bool get ready => _api != null && _cli != null;

  /// Boots (or reuses) the Surge daemon and wires up the read/write clients.
  /// Also re-attaches to any torrent engine left running by a prior launch.
  Future<void> ensureDaemon() async {
    final info = await _daemon.ensureRunning();
    _api?.dispose();
    _api = SurgeApi(baseUrl: info.baseUrl, token: info.token);
    _cli = SurgeCli(binary: info.binary, env: info.env);
    await _aria2.attach();
  }

  Future<List<DownloadTask>> fetchTasks() async {
    final api = _api;
    if (api == null) {
      throw StateError('Surge 守护进程尚未就绪');
    }
    final surge = await api.list();
    if (_aria2.ready) {
      try {
        final torrents = await _aria2.tasks();
        if (torrents.isNotEmpty) {
          return <DownloadTask>[...torrents, ...surge];
        }
      } catch (_) {
        // Torrent engine is best-effort; never break Surge polling.
      }
    }
    return surge;
  }

  SurgeCli get cli {
    final cli = _cli;
    if (cli == null) {
      throw StateError('Surge 守护进程尚未就绪');
    }
    return cli;
  }

  // ---- Unified add + mutations ----------------------------------------------

  /// Adds a link with engine routing:
  ///   * magnet / torrent                 -> aria2 (BitTorrent)
  ///   * HLS / DASH manifest              -> rejected with a clear message (ffmpeg)
  ///   * HTTP w/ referer / UA / headers   -> aria2 (HTTP, carrying them)
  ///   * everything else                  -> Surge (HTTP)
  ///
  /// The Surge CLI cannot attach a custom User-Agent or request headers, so any
  /// download that needs them is routed through aria2 (which can).
  ///
  /// [outName] forces the saved filename (used to keep a renamed copy on a
  /// duplicate). aria2 honours it via `out`; Surge ignores it but already
  /// auto-suffixes on a name collision, so a distinct copy is kept either way.
  Future<CliResult> add(
    String url, {
    String? outputDir,
    String? referer,
    String? outName,
    String? userAgent,
    Map<String, String>? headers,
  }) async {
    if (LinkClassifier.isTorrentLink(url)) {
      try {
        await _aria2.ensureRunning(defaultDir: outputDir);
        final gid = await _aria2.add(url, dir: outputDir);
        return CliResult(true, gid);
      } on Aria2NotInstalled {
        return const CliResult(false, '磁力 / 种子引擎不可用');
      } catch (e) {
        return CliResult(false, '$e');
      }
    }

    if (LinkClassifier.isStreamingManifest(url)) {
      return const CliResult(
        false,
        'HLS/DASH 流媒体暂不支持直接下载(切片合并需 ffmpeg)',
      );
    }

    final hasReferer = referer != null && referer.trim().isNotEmpty;
    final hasUserAgent = userAgent != null && userAgent.trim().isNotEmpty;
    final hasHeaders = headers != null && headers.isNotEmpty;
    if (hasReferer || hasUserAgent || hasHeaders) {
      try {
        await _aria2.ensureRunning(defaultDir: outputDir);
        final gid = await _aria2.add(
          url,
          dir: outputDir,
          referer: referer,
          out: outName,
          userAgent: userAgent,
          headers: headers,
        );
        return CliResult(true, gid);
      } on Aria2NotInstalled {
        // No torrent engine: fall back to Surge (loses UA/headers, but downloads).
        return cli.add(url, outputDir: outputDir);
      } catch (e) {
        return CliResult(false, '$e');
      }
    }

    return cli.add(url, outputDir: outputDir);
  }

  Future<CliResult> pause(String id) => _isAria2(id)
      ? _wrapAria2(() => _aria2.pause(_gid(id)))
      : cli.pause(id);

  Future<CliResult> resume(String id) => _isAria2(id)
      ? _wrapAria2(() => _aria2.resume(_gid(id)))
      : cli.resume(id);

  Future<CliResult> remove(String id, {bool purge = false}) => _isAria2(id)
      ? _wrapAria2(() => _aria2.remove(_gid(id), purge: purge))
      : cli.remove(id, purge: purge);

  Future<CliResult> pauseAll() async {
    final result = await cli.pauseAll();
    if (_aria2.ready) {
      try {
        await _aria2.pauseAll();
      } catch (_) {}
    }
    return result;
  }

  Future<CliResult> resumeAll() async {
    final result = await cli.resumeAll();
    if (_aria2.ready) {
      try {
        await _aria2.resumeAll();
      } catch (_) {}
    }
    return result;
  }

  Future<CliResult> clean() async {
    final result = await cli.clean();
    if (_aria2.ready) {
      try {
        await _aria2.clean();
      } catch (_) {}
    }
    return result;
  }

  Future<CliResult> limitGlobal(String speed) async {
    final result = await cli.limitGlobal(speed);
    if (_aria2.ready) {
      try {
        await _aria2.setLimit(speed);
      } catch (_) {}
    }
    return result;
  }

  bool _isAria2(String id) => id.startsWith(_aria2Prefix);

  String _gid(String id) => id.substring(_aria2Prefix.length);

  Future<CliResult> _wrapAria2(Future<void> Function() action) async {
    try {
      await action();
      return const CliResult(true, '');
    } catch (e) {
      return CliResult(false, '$e');
    }
  }

  Future<void> stopDaemon() => _daemon.stop();

  void dispose() {
    _api?.dispose();
    _aria2.dispose();
  }
}
