import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/engine/download_engine.dart';
import '../data/models/download_task.dart';
import '../data/repository/download_repository.dart';
import '../data/services/duplicate_detector.dart';

/// Sidebar filter selection.
enum DownloadFilter { all, active, completed, failed }

/// Ordering applied to the visible task list.
///   * addedDesc — most recently added first. Surge always reports
///     `added_at: 0`, so we order by a locally tracked "first seen" sequence
///     (persisted across restarts) as a stand-in download time.
///   * nameAsc — by filename, A→Z (case-insensitive, by first character).
enum DownloadSort { addedDesc, nameAsc }

/// Daemon connection lifecycle for the UI.
enum DaemonConnection { connecting, connected, error, notInstalled }

/// Result of an add attempt that may have been cancelled at the duplicate prompt.
class AddOutcome {
  /// User chose not to download at the duplicate prompt.
  final bool cancelled;

  /// Error message, or null on success.
  final String? error;

  const AddOutcome._(this.cancelled, this.error);
  const AddOutcome.ok() : this._(false, null);
  const AddOutcome.userCancelled() : this._(true, null);
  const AddOutcome.failed(String message) : this._(false, message);

  bool get ok => !cancelled && error == null;
}

class DownloadController extends ChangeNotifier {
  final DownloadRepository _repo;
  final DuplicateDetector _detector = DuplicateDetector();

  DownloadController(this._repo);

  DaemonConnection connection = DaemonConnection.connecting;
  String? errorMessage;
  DownloadFilter filter = DownloadFilter.all;
  DownloadSort sort = DownloadSort.addedDesc;
  String? defaultOutputDir;

  /// Global default User-Agent + request headers, applied to every direct
  /// HTTP(S) download (kept in sync with [SettingsController]). Per-add values
  /// passed to [addUrl] / [addWithDuplicateCheck] override / merge on top.
  String defaultUserAgent = '';
  Map<String, String> defaultHeaders = const {};

  /// Keeps the global download UA / headers in sync with user settings.
  void setDownloadHeaders({
    required String userAgent,
    required Map<String, String> headers,
  }) {
    defaultUserAgent = userAgent;
    defaultHeaders = headers;
  }

  /// Per-add UA overrides the global default; an empty override falls back to it.
  String? _effectiveUserAgent(String? override) {
    final o = override?.trim() ?? '';
    if (o.isNotEmpty) return o;
    final d = defaultUserAgent.trim();
    return d.isNotEmpty ? d : null;
  }

  /// Per-add headers are merged on top of the global defaults (per-add wins).
  Map<String, String>? _effectiveHeaders(Map<String, String>? override) {
    final merged = <String, String>{...defaultHeaders};
    if (override != null) merged.addAll(override);
    return merged.isEmpty ? null : merged;
  }

  List<DownloadTask> _tasks = const [];
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  int _consecutiveFailures = 0;

  // ---- Sort + persistence ----------------------------------------------------

  static const _kSort = 'download_sort';
  static const _kOrderMap = 'download_added_order';
  static const _kOrderSeq = 'download_added_seq';

  SharedPreferences? _prefs;

  /// Locally tracked "first seen" order per task id, used as a stand-in for a
  /// real added-at timestamp (Surge always reports `added_at: 0`). Monotonic:
  /// newer tasks get a higher value, so descending order surfaces the latest
  /// downloads first. Persisted so the ordering survives app restarts.
  final Map<String, int> _addedOrder = {};
  int _orderSeq = 0;

  // ---- Derived state ---------------------------------------------------------

  List<DownloadTask> get tasks => _filtered();
  List<DownloadTask> get allTasks => _tasks;

  int get countAll => _tasks.length;
  int get countActive => _tasks.where((t) => t.isActive).length;
  int get countDownloading =>
      _tasks.where((t) => t.status == DownloadStatus.downloading).length;
  int get countCompleted =>
      _tasks.where((t) => t.status == DownloadStatus.completed).length;
  int get countFailed =>
      _tasks.where((t) => t.status == DownloadStatus.error).length;

  double get totalSpeedBytesPerSec => _tasks
      .where((t) => t.status == DownloadStatus.downloading)
      .fold(0.0, (sum, t) => sum + t.speedBytesPerSec);

  bool get isConnected => connection == DaemonConnection.connected;

  List<DownloadTask> _filtered() {
    final Iterable<DownloadTask> base;
    switch (filter) {
      case DownloadFilter.all:
        base = _tasks;
        break;
      case DownloadFilter.active:
        base = _tasks.where((t) => t.isActive);
        break;
      case DownloadFilter.completed:
        base = _tasks.where((t) => t.status == DownloadStatus.completed);
        break;
      case DownloadFilter.failed:
        base = _tasks.where((t) => t.status == DownloadStatus.error);
        break;
    }
    return _sorted(base);
  }

  /// Returns a new list ordered by [sort]. Comparators are total (id breaks
  /// ties) so ordering is deterministic regardless of `List.sort` stability.
  List<DownloadTask> _sorted(Iterable<DownloadTask> tasks) {
    final list = tasks.toList();
    switch (sort) {
      case DownloadSort.addedDesc:
        list.sort((a, b) {
          final cmp =
              (_addedOrder[b.id] ?? -1).compareTo(_addedOrder[a.id] ?? -1);
          return cmp != 0 ? cmp : a.id.compareTo(b.id);
        });
        break;
      case DownloadSort.nameAsc:
        list.sort((a, b) {
          final cmp = _nameKey(a.filename).compareTo(_nameKey(b.filename));
          return cmp != 0 ? cmp : a.id.compareTo(b.id);
        });
        break;
    }
    return list;
  }

  String _nameKey(String name) => name.trim().toLowerCase();

  int countFor(DownloadFilter f) {
    switch (f) {
      case DownloadFilter.all:
        return countAll;
      case DownloadFilter.active:
        return countActive;
      case DownloadFilter.completed:
        return countCompleted;
      case DownloadFilter.failed:
        return countFailed;
    }
  }

  // ---- Mutations -------------------------------------------------------------

  void setFilter(DownloadFilter value) {
    if (filter == value) return;
    filter = value;
    _safeNotify();
  }

  void setSort(DownloadSort value) {
    if (sort == value) return;
    sort = value;
    _prefs?.setString(_kSort, value.name);
    _safeNotify();
  }

  void setDefaultOutputDir(String? dir) {
    defaultOutputDir = dir;
    _safeNotify();
  }

  /// Connects to the daemon (starting it if needed) and begins polling.
  Future<void> bootstrap() async {
    await _ensurePrefs();
    connection = DaemonConnection.connecting;
    errorMessage = null;
    _safeNotify();
    try {
      await _repo.ensureDaemon();
      connection = DaemonConnection.connected;
      _consecutiveFailures = 0;
      await _poll();
      _scheduleNext();
    } on EngineUnavailable catch (e) {
      connection = DaemonConnection.notInstalled;
      errorMessage = e.message;
    } catch (e) {
      connection = DaemonConnection.error;
      errorMessage = '$e';
    }
    _safeNotify();
  }

  void retry() => bootstrap();

  /// Loads the persisted sort preference + added-order map. Best-effort: any
  /// failure leaves the in-memory defaults untouched and never blocks booting.
  Future<void> _ensurePrefs() async {
    if (_prefs != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      sort = _sortFromName(prefs.getString(_kSort));
      _orderSeq = prefs.getInt(_kOrderSeq) ?? 0;
      final raw = prefs.getString(_kOrderMap);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final v = value is int ? value : int.tryParse('$value');
            if (v != null) _addedOrder['$key'] = v;
          });
        }
      }
    } catch (_) {
      // Preferences are a progressive enhancement; defaults are fine.
    }
  }

  /// Records the first time each task id is seen (a monotonically increasing
  /// sequence) and drops ids that have disappeared, then persists when changed.
  void _trackOrder(List<DownloadTask> tasks) {
    var changed = false;
    final present = <String>{};
    for (final task in tasks) {
      present.add(task.id);
      if (!_addedOrder.containsKey(task.id)) {
        _addedOrder[task.id] = _orderSeq++;
        changed = true;
      }
    }
    final stale = _addedOrder.keys.where((id) => !present.contains(id)).toList();
    if (stale.isNotEmpty) {
      for (final id in stale) {
        _addedOrder.remove(id);
      }
      changed = true;
    }
    if (changed) {
      _prefs?.setString(_kOrderMap, jsonEncode(_addedOrder));
      _prefs?.setInt(_kOrderSeq, _orderSeq);
    }
  }

  static DownloadSort _sortFromName(String? name) {
    switch (name) {
      case 'nameAsc':
        return DownloadSort.nameAsc;
      case 'addedDesc':
      default:
        return DownloadSort.addedDesc;
    }
  }

  Future<String?> addUrl(
    String url, {
    String? outputDir,
    String? referer,
    String? userAgent,
    Map<String, String>? headers,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'URL 不能为空';
    if (!_repo.ready) return '下载引擎尚未就绪';
    final dir = (outputDir != null && outputDir.trim().isNotEmpty)
        ? outputDir
        : defaultOutputDir;
    final result = await _repo.add(
      trimmed,
      outputDir: dir,
      referer: referer,
      userAgent: _effectiveUserAgent(userAgent),
      headers: _effectiveHeaders(headers),
    );
    await _poll();
    return result.ok ? null : result.message;
  }

  /// Adds [url], but first (when [checkEnabled]) inspects the destination
  /// directory for an existing same-name / same-size file. On a hit, [onDuplicate]
  /// is invoked to obtain the user's [DuplicateDecision]:
  ///   * cancel  -> nothing is downloaded;
  ///   * rename  -> download kept under a free `name(1).ext` name (both kept);
  ///   * replace -> the matched originals are deleted, then a normal add runs.
  Future<AddOutcome> addWithDuplicateCheck(
    String url, {
    String? outputDir,
    String? referer,
    String? userAgent,
    Map<String, String>? headers,
    required bool checkEnabled,
    required Future<DuplicateDecision> Function(DuplicateReport report)
        onDuplicate,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return const AddOutcome.failed('URL 不能为空');
    if (!_repo.ready) return const AddOutcome.failed('下载引擎尚未就绪');

    final dir = (outputDir != null && outputDir.trim().isNotEmpty)
        ? outputDir.trim()
        : defaultOutputDir;
    final effUserAgent = _effectiveUserAgent(userAgent);
    final effHeaders = _effectiveHeaders(headers);

    if (checkEnabled &&
        dir != null &&
        dir.isNotEmpty &&
        _detector.isCheckable(trimmed)) {
      DuplicateReport? report;
      try {
        report = await _detector.inspect(
          url: trimmed,
          dir: dir,
          referer: referer,
        );
      } catch (_) {
        report = null;
      }

      if (report != null && report.hasMatches) {
        final decision = await onDuplicate(report);
        switch (decision) {
          case DuplicateDecision.cancel:
            return const AddOutcome.userCancelled();
          case DuplicateDecision.replace:
            await _detector.deleteFiles(report.matchPaths);
            break; // fall through to a normal add (original filename).
          case DuplicateDecision.rename:
            final freeName = _detector.freeNameIn(dir, report.remoteName);
            final renamed = await _repo.add(
              trimmed,
              outputDir: dir,
              referer: referer,
              outName: freeName,
              userAgent: effUserAgent,
              headers: effHeaders,
            );
            await _poll();
            return renamed.ok
                ? const AddOutcome.ok()
                : AddOutcome.failed(renamed.message);
        }
      }
    }

    final result = await _repo.add(
      trimmed,
      outputDir: dir,
      referer: referer,
      userAgent: effUserAgent,
      headers: effHeaders,
    );
    await _poll();
    return result.ok ? const AddOutcome.ok() : AddOutcome.failed(result.message);
  }

  Future<void> pause(String id) => _mutate(() => _repo.pause(id));
  Future<void> resume(String id) => _mutate(() => _repo.resume(id));
  Future<void> remove(String id, {bool purge = false}) =>
      _mutate(() => _repo.remove(id, purge: purge));
  Future<void> pauseAll() => _mutate(() => _repo.pauseAll());
  Future<void> resumeAll() => _mutate(() => _repo.resumeAll());
  Future<void> clean() => _mutate(() => _repo.clean());

  Future<String?> setGlobalLimit(String speed) async {
    if (!_repo.ready) return '下载引擎尚未就绪';
    final result = await _repo.limitGlobal(speed);
    await _poll();
    return result.ok ? null : result.message;
  }

  Future<void> _mutate(Future<Object?> Function() action) async {
    if (!_repo.ready) return;
    await action();
    await _poll();
  }

  // ---- Polling ---------------------------------------------------------------

  void _scheduleNext() {
    _timer?.cancel();
    if (_disposed || connection == DaemonConnection.notInstalled) return;
    final interval = countDownloading > 0
        ? const Duration(milliseconds: 700)
        : const Duration(seconds: 2);
    _timer = Timer(interval, () async {
      await _poll();
      _scheduleNext();
    });
  }

  Future<void> _poll() async {
    if (_polling || _disposed) return;
    if (connection == DaemonConnection.notInstalled) return;
    _polling = true;
    try {
      final tasks = await _repo.fetchTasks();
      _tasks = tasks;
      _trackOrder(tasks);
      _consecutiveFailures = 0;
      if (connection != DaemonConnection.connected) {
        connection = DaemonConnection.connected;
        errorMessage = null;
      }
      _safeNotify();
    } catch (e) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3 &&
          connection == DaemonConnection.connected) {
        connection = DaemonConnection.error;
        errorMessage = '与下载引擎的连接中断';
        _safeNotify();
      }
    } finally {
      _polling = false;
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _detector.dispose();
    _repo.dispose();
    super.dispose();
  }
}
