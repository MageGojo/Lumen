import '../../core/utils/link_classifier.dart';
import '../models/download_task.dart';
import '../services/aria2_service.dart';
import 'download_engine.dart';

/// Windows engine: a single aria2 daemon drives **everything** — normal HTTP
/// (multi-connection via the daemon's global `--split` options), magnet and
/// `.torrent` — so the Windows build needs no Surge binary at all.
///
/// aria2 is spawned detached and re-attached on the next launch (a saved
/// session restores the task list), mirroring how macOS keeps its torrent
/// engine alive across restarts.
class Aria2Engine implements DownloadEngine {
  final Aria2Service _aria2 = Aria2Service();

  static const String _prefix = 'aria2:';

  @override
  bool get ready => _aria2.ready;

  @override
  Future<void> start() async {
    // Prefer re-attaching to a daemon left running by a previous launch so
    // in-flight downloads survive an app restart.
    if (await _aria2.attach()) return;
    try {
      await _aria2.ensureRunning();
    } on Aria2NotInstalled {
      throw const EngineUnavailable(
        '未检测到内置 aria2 下载引擎,请重新安装 Lumen。',
      );
    } catch (e) {
      throw EngineUnavailable('下载引擎启动失败:$e');
    }
  }

  @override
  Future<List<DownloadTask>> fetchTasks() => _aria2.tasks();

  @override
  Future<CliResult> add(
    String url, {
    String? outputDir,
    String? referer,
    String? outName,
    String? userAgent,
    Map<String, String>? headers,
  }) async {
    if (LinkClassifier.isStreamingManifest(url)) {
      return const CliResult(
        false,
        'HLS/DASH 流媒体暂不支持直接下载(切片合并需 ffmpeg)',
      );
    }
    // aria2 transparently handles magnet / .torrent / http(s); extra options
    // (out / UA / headers) are ignored for torrents, honoured for HTTP.
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
      return const CliResult(false, '下载引擎不可用');
    } catch (e) {
      return CliResult(false, '$e');
    }
  }

  @override
  Future<CliResult> pause(String id) => _wrap(() => _aria2.pause(_gid(id)));

  @override
  Future<CliResult> resume(String id) => _wrap(() => _aria2.resume(_gid(id)));

  @override
  Future<CliResult> remove(String id, {bool purge = false}) =>
      _wrap(() => _aria2.remove(_gid(id), purge: purge));

  @override
  Future<CliResult> pauseAll() => _wrap(() => _aria2.pauseAll());

  @override
  Future<CliResult> resumeAll() => _wrap(() => _aria2.resumeAll());

  @override
  Future<CliResult> clean() => _wrap(() => _aria2.clean());

  @override
  Future<CliResult> limitGlobal(String speed) =>
      _wrap(() => _aria2.setLimit(speed));

  // Single engine: keep the detached daemon alive across app exits so saved
  // sessions + `--continue` resume downloads on the next launch.
  @override
  Future<void> stop() async {}

  @override
  void dispose() => _aria2.dispose();

  String _gid(String id) =>
      id.startsWith(_prefix) ? id.substring(_prefix.length) : id;

  Future<CliResult> _wrap(Future<void> Function() action) async {
    try {
      await action();
      return const CliResult(true, '');
    } catch (e) {
      return CliResult(false, '$e');
    }
  }
}
