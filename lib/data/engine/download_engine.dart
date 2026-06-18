import '../models/download_task.dart';

/// Result of a download-engine operation (add / pause / remove / …).
///
/// Historically named for the Surge CLI; it is now the neutral result type
/// shared by every [DownloadEngine] implementation.
class CliResult {
  final bool ok;
  final String message;
  const CliResult(this.ok, this.message);
}

/// Thrown by [DownloadEngine.start] when the underlying engine binary is
/// missing or its daemon cannot be brought up. The UI surfaces this as a
/// dedicated "engine not available" state (with a platform-specific hint).
class EngineUnavailable implements Exception {
  final String message;
  const EngineUnavailable(this.message);
  @override
  String toString() => message;
}

/// Platform-agnostic download backend.
///
/// Two implementations exist, selected by [DownloadRepository] at runtime:
///   * `SurgeAria2Engine` — macOS: Surge (HTTP) + aria2 (BT / header'd HTTP);
///   * `Aria2Engine`      — Windows: aria2 only (HTTP + BT in one engine).
///
/// Task ids are engine-tagged so per-task mutations route correctly. The
/// controller treats this surface uniformly regardless of platform.
abstract class DownloadEngine {
  /// Whether the engine is booted and ready to accept adds / mutations.
  bool get ready;

  /// Boots (or re-attaches to) the engine's daemon(s).
  ///
  /// Throws [EngineUnavailable] if the engine binary is missing or the daemon
  /// cannot be started.
  Future<void> start();

  /// Current task list, merged across whatever backends the engine drives.
  Future<List<DownloadTask>> fetchTasks();

  /// Adds a link. Routing (torrent vs HTTP) is the engine's responsibility.
  ///
  /// [outName] forces the saved filename (used to keep a renamed copy when a
  /// duplicate is detected).
  Future<CliResult> add(
    String url, {
    String? outputDir,
    String? referer,
    String? outName,
    String? userAgent,
    Map<String, String>? headers,
  });

  Future<CliResult> pause(String id);
  Future<CliResult> resume(String id);
  Future<CliResult> remove(String id, {bool purge = false});
  Future<CliResult> pauseAll();
  Future<CliResult> resumeAll();
  Future<CliResult> clean();
  Future<CliResult> limitGlobal(String speed);

  /// Best-effort shutdown of any daemons the engine owns.
  Future<void> stop();

  /// Releases clients/sockets held by the engine.
  void dispose();
}
