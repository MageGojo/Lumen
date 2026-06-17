import 'dart:io';

import 'surge_locator.dart';

/// Thrown when the `surge` binary cannot be found on the system.
class SurgeNotInstalled implements Exception {
  const SurgeNotInstalled();
  @override
  String toString() => 'Surge 未安装';
}

/// Thrown when the daemon could not be started or queried.
class SurgeDaemonError implements Exception {
  final String message;
  const SurgeDaemonError(this.message);
  @override
  String toString() => message;
}

/// Connection details for a running Surge daemon.
class DaemonInfo {
  final String binary;
  final int port;
  final String token;

  const DaemonInfo({
    required this.binary,
    required this.port,
    required this.token,
  });

  String get baseUrl => 'http://127.0.0.1:$port';

  Map<String, String> get env => {
        'SURGE_HOST': '127.0.0.1:$port',
        'SURGE_TOKEN': token,
      };
}

/// Manages the lifecycle of the embedded Surge background daemon.
class SurgeDaemon {
  DaemonInfo? info;

  static final RegExp _portPattern = RegExp(r'[Pp]ort:?\s*(\d+)');

  /// Ensures a daemon is running and returns its connection info.
  Future<DaemonInfo> ensureRunning() async {
    final binary = await SurgeLocator.resolve();
    if (binary == null) throw const SurgeNotInstalled();

    var port = await _statusPort(binary);
    if (port == null) {
      await _start(binary);
      for (var attempt = 0; attempt < 24; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        port = await _statusPort(binary);
        if (port != null) break;
      }
      if (port == null) {
        throw const SurgeDaemonError('Surge 守护进程启动超时');
      }
    }

    final token = await _token(binary, port);
    if (token.isEmpty) {
      throw const SurgeDaemonError('无法获取 Surge 鉴权 token');
    }

    final resolved = DaemonInfo(binary: binary, port: port, token: token);
    info = resolved;
    return resolved;
  }

  Future<int?> _statusPort(String binary) async {
    try {
      final result = await Process.run(binary, ['server', 'status'])
          .timeout(const Duration(seconds: 6));
      final output = '${result.stdout}${result.stderr}';
      final match = _portPattern.firstMatch(output);
      if (match != null) return int.tryParse(match.group(1)!);
    } catch (_) {
      // treated as "not running"
    }
    return null;
  }

  Future<void> _start(String binary) async {
    // Detached so the daemon outlives this spawn call and our app process.
    await Process.start(
      binary,
      ['server', 'start'],
      mode: ProcessStartMode.detached,
    );
  }

  Future<String> _token(String binary, int port) async {
    try {
      final result = await Process.run(
        binary,
        ['token', '--host', '127.0.0.1:$port'],
      ).timeout(const Duration(seconds: 6));
      return '${result.stdout}'.trim().split('\n').first.trim();
    } catch (_) {
      return '';
    }
  }

  /// Stops the daemon (best effort).
  Future<void> stop() async {
    final binary = info?.binary ?? await SurgeLocator.resolve();
    if (binary == null) return;
    try {
      await Process.run(binary, ['server', 'stop'])
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // ignore
    }
  }
}
