import 'dart:io';

/// Native macOS folder chooser via AppleScript (no extra dependency needed).
class FolderPicker {
  const FolderPicker._();

  static Future<String?> choose({String prompt = '选择保存目录'}) async {
    try {
      final escaped = prompt.replaceAll('"', '\\"');
      final script = 'POSIX path of (choose folder with prompt "$escaped")';
      final result = await Process.run('osascript', ['-e', script]);
      if (result.exitCode == 0) {
        var path = '${result.stdout}'.trim();
        if (path.isEmpty) return null;
        if (path.length > 1 && path.endsWith('/')) {
          path = path.substring(0, path.length - 1);
        }
        return path;
      }
    } catch (_) {
      // user cancelled or osascript unavailable
    }
    return null;
  }
}

/// Reveals a file or folder in Finder.
class FinderReveal {
  const FinderReveal._();

  static Future<void> reveal(String path) async {
    if (path.isEmpty) return;
    try {
      await Process.run('open', ['-R', path]);
    } catch (_) {
      // ignore
    }
  }
}
