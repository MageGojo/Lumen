import '../../core/utils/link_classifier.dart';
import '../models/download_task.dart';
import '../services/aria2_service.dart';
import '../services/surge_api.dart';
import '../services/surge_cli.dart';
import '../services/surge_daemon.dart';
import 'download_engine.dart';

/// macOS engine: Surge drives normal HTTP downloads; aria2 handles
/// `magnet:` / `.torrent` plus any HTTP download that must carry a custom
/// UA / Referer / headers (the Surge CLI cannot).
///
/// This is the project's original dual-engine behaviour, unchanged, now sitting
/// behind the [DownloadEngine] interface so the Windows build can swap in a
/// single-engine (aria2-only) implementation instead.
class SurgeAria2Engine implements DownloadEngine {
  final SurgeDaemon _daemon = SurgeDaemon();
  final Aria2Service _aria2 = Aria2Service();
  SurgeApi? _api;
  SurgeCli? _cli;

  static const String _aria2Prefix = 'aria2:';

  @override
  bool get ready => _api != null && _cli != null;

  @override
  Future<void> start() async {
    try {
      final info = await _daemon.ensureRunning();
      _api?.dispose();
      _api = SurgeApi(baseUrl: info.baseUrl, token: info.token);
      _cli = SurgeCli(binary: info.binary, env: info.env);
      await _aria2.attach();
    } on SurgeNotInstalled {
      throw const EngineUnavailable(
        '未检测到 surge。请先安装(例如 brew install surge),再点击重试。',
      );
    }
  }

  @override
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

  SurgeCli get _cliOrThrow {
    final cli = _cli;
    if (cli == null) {
      throw StateError('Surge 守护进程尚未就绪');
    }
    return cli;
  }

  @override
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
        return _cliOrThrow.add(url, outputDir: outputDir);
      } catch (e) {
        return CliResult(false, '$e');
      }
    }

    return _cliOrThrow.add(url, outputDir: outputDir);
  }

  @override
  Future<CliResult> pause(String id) => _isAria2(id)
      ? _wrapAria2(() => _aria2.pause(_gid(id)))
      : _cliOrThrow.pause(id);

  @override
  Future<CliResult> resume(String id) => _isAria2(id)
      ? _wrapAria2(() => _aria2.resume(_gid(id)))
      : _cliOrThrow.resume(id);

  @override
  Future<CliResult> remove(String id, {bool purge = false}) => _isAria2(id)
      ? _wrapAria2(() => _aria2.remove(_gid(id), purge: purge))
      : _cliOrThrow.remove(id, purge: purge);

  @override
  Future<CliResult> pauseAll() async {
    final result = await _cliOrThrow.pauseAll();
    if (_aria2.ready) {
      try {
        await _aria2.pauseAll();
      } catch (_) {}
    }
    return result;
  }

  @override
  Future<CliResult> resumeAll() async {
    final result = await _cliOrThrow.resumeAll();
    if (_aria2.ready) {
      try {
        await _aria2.resumeAll();
      } catch (_) {}
    }
    return result;
  }

  @override
  Future<CliResult> clean() async {
    final result = await _cliOrThrow.clean();
    if (_aria2.ready) {
      try {
        await _aria2.clean();
      } catch (_) {}
    }
    return result;
  }

  @override
  Future<CliResult> limitGlobal(String speed) async {
    final result = await _cliOrThrow.limitGlobal(speed);
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

  @override
  Future<void> stop() => _daemon.stop();

  @override
  void dispose() {
    _api?.dispose();
    _aria2.dispose();
  }
}
