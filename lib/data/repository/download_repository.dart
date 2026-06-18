import 'dart:io';

import '../engine/aria2_engine.dart';
import '../engine/download_engine.dart';
import '../engine/surge_aria2_engine.dart';
import '../models/download_task.dart';

/// Facade over the platform-appropriate [DownloadEngine]:
///   * macOS   -> [SurgeAria2Engine] — Surge (HTTP) + aria2 (BT) dual engine;
///   * Windows -> [Aria2Engine]      — aria2 single engine (HTTP + BT).
///
/// Keeps the original method surface so [DownloadController] stays
/// platform-agnostic; all calls delegate to the selected engine.
class DownloadRepository {
  final DownloadEngine _engine =
      Platform.isWindows ? Aria2Engine() : SurgeAria2Engine();

  bool get ready => _engine.ready;

  /// Boots (or re-attaches to) the engine. Throws [EngineUnavailable] if the
  /// engine binary is missing or its daemon cannot be started.
  Future<void> ensureDaemon() => _engine.start();

  Future<List<DownloadTask>> fetchTasks() => _engine.fetchTasks();

  Future<CliResult> add(
    String url, {
    String? outputDir,
    String? referer,
    String? outName,
    String? userAgent,
    Map<String, String>? headers,
  }) =>
      _engine.add(
        url,
        outputDir: outputDir,
        referer: referer,
        outName: outName,
        userAgent: userAgent,
        headers: headers,
      );

  Future<CliResult> pause(String id) => _engine.pause(id);

  Future<CliResult> resume(String id) => _engine.resume(id);

  Future<CliResult> remove(String id, {bool purge = false}) =>
      _engine.remove(id, purge: purge);

  Future<CliResult> pauseAll() => _engine.pauseAll();

  Future<CliResult> resumeAll() => _engine.resumeAll();

  Future<CliResult> clean() => _engine.clean();

  Future<CliResult> limitGlobal(String speed) => _engine.limitGlobal(speed);

  Future<void> stopDaemon() => _engine.stop();

  void dispose() => _engine.dispose();
}
