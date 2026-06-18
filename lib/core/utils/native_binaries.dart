import 'dart:io';

import 'package:flutter/services.dart';

/// Ships the download engines inside the app so nothing has to be installed
/// separately (Homebrew on macOS, anything on Windows).
///
///   * macOS  — `surge` + `aria2c` (and aria2's relocated dylib closure),
///              bundled under `native/macos/bin/`, made executable on extract.
///   * Windows — `aria2c.exe` (single static binary), bundled under
///              `native/windows/bin/`; aria2 alone drives every download.
///
/// On first launch (or after a version bump) the bundled binaries are unpacked
/// into the per-user support directory; their paths are then exposed to the
/// engine locators.
class NativeBinaries {
  NativeBinaries._();

  /// Bump to force a re-extraction after the bundled binaries change.
  static const String _version = '1';

  static bool _done = false;

  /// Absolute path to the extracted `surge` (macOS only), or null.
  static String? surgePath;

  /// Absolute path to the extracted `aria2c` / `aria2c.exe`, or null.
  static String? aria2cPath;

  /// The per-user support directory (`…/Lumen`), used e.g. for aria2's saved
  /// session file. Set once [ensureExtracted] has resolved the platform paths.
  static String? supportDir;

  static String get _assetDir =>
      Platform.isWindows ? 'native/windows/bin/' : 'native/macos/bin/';

  /// Resolves the per-user support root (`…/Lumen`) per platform.
  static String? _supportRoot() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return '$appData\\Lumen';
      }
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        return '$profile\\AppData\\Roaming\\Lumen';
      }
      return null;
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return '$home/Library/Application Support/Lumen';
  }

  /// Extracts the bundled engines once. Best-effort: on any failure the
  /// locators fall back to a system-installed binary.
  static Future<void> ensureExtracted() async {
    if (_done) return;
    _done = true;
    try {
      final root = _supportRoot();
      if (root == null) return;
      supportDir = root;

      final sep = Platform.pathSeparator;
      final destPath = '$root${sep}bin';
      final destDir = Directory(destPath);
      final marker = File('$destPath$sep.extracted_v$_version');

      if (!await marker.exists()) {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        final keys = manifest
            .listAssets()
            .where((k) => k.startsWith(_assetDir))
            .toList();
        if (keys.isEmpty) return;

        if (await destDir.exists()) {
          await destDir.delete(recursive: true);
        }
        await destDir.create(recursive: true);

        for (final key in keys) {
          final leaf = key.substring(_assetDir.length);
          // Skip the directory placeholder kept in git so the asset dir exists.
          if (leaf.isEmpty || leaf == '.gitkeep') continue;
          final data = await rootBundle.load(key);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          final file = File('$destPath$sep$leaf');
          await file.writeAsBytes(bytes, flush: true);
        }

        if (!Platform.isWindows) {
          await _makeExecutable('$destPath${sep}surge');
          await _makeExecutable('$destPath${sep}aria2c');
        }
        await marker.create();
      }

      if (Platform.isWindows) {
        final aria = File('$destPath${sep}aria2c.exe');
        if (await aria.exists()) aria2cPath = aria.path;
      } else {
        final surge = File('$destPath${sep}surge');
        final aria = File('$destPath${sep}aria2c');
        if (await surge.exists()) surgePath = surge.path;
        if (await aria.exists()) aria2cPath = aria.path;
      }
    } catch (_) {
      // Fall back to system-installed binaries.
    }
  }

  static Future<void> _makeExecutable(String path) async {
    try {
      await Process.run('/bin/chmod', ['755', path]);
    } catch (_) {
      // ignore; the file may already be executable
    }
  }
}
