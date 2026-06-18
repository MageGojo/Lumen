import 'dart:io';

import '../../core/utils/native_binaries.dart';

/// Resolves the absolute path to the `surge` executable.
///
/// The app-bundled binary (extracted by [NativeBinaries]) is preferred so no
/// Homebrew install is required. A GUI app launched from Finder does not
/// inherit the shell `PATH`, so we then probe well-known locations and finally
/// fall back to a login-shell lookup.
class SurgeLocator {
  static String? _cached;

  static const List<String> _candidates = [
    '/opt/homebrew/bin/surge',
    '/usr/local/bin/surge',
    '/usr/bin/surge',
  ];

  static Future<String?> resolve() async {
    // Surge is a macOS-only engine; the Windows build uses aria2 exclusively.
    if (!Platform.isMacOS) return null;
    if (_cached != null) return _cached;

    final bundled = NativeBinaries.surgePath;
    if (bundled != null && await File(bundled).exists()) {
      _cached = bundled;
      return bundled;
    }

    for (final path in _candidates) {
      if (await File(path).exists()) {
        _cached = path;
        return path;
      }
    }

    try {
      final result = await Process.run('/bin/zsh', ['-lc', 'command -v surge'])
          .timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final path = '${result.stdout}'.trim().split('\n').first.trim();
        if (path.isNotEmpty && await File(path).exists()) {
          _cached = path;
          return path;
        }
      }
    } catch (_) {
      // ignore and report as not found
    }
    return null;
  }
}
