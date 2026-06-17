import 'dart:io';

import 'package:flutter/services.dart';

/// Ships `surge` + `aria2c` (and aria2's relocated dylib closure) inside the
/// app so neither engine has to be installed via Homebrew.
///
/// The binaries are bundled as Flutter assets under `native/macos/bin/`. On
/// first launch (or after a version bump) they are unpacked into Application
/// Support and made executable; their paths are then exposed to the locators.
class NativeBinaries {
  NativeBinaries._();

  static const String _assetDir = 'native/macos/bin/';

  /// Bump to force a re-extraction after the bundled binaries change.
  static const String _version = '1';

  static bool _done = false;

  /// Absolute path to the extracted `surge`, or null if unavailable.
  static String? surgePath;

  /// Absolute path to the extracted `aria2c`, or null if unavailable.
  static String? aria2cPath;

  /// Extracts the bundled engines once. Best-effort: on any failure the
  /// locators fall back to a system-installed binary.
  static Future<void> ensureExtracted() async {
    if (_done) return;
    _done = true;
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;

      final destDir = Directory(
        '$home/Library/Application Support/Lumen/bin',
      );
      final marker = File('${destDir.path}/.extracted_v$_version');

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
          if (leaf.isEmpty) continue;
          final data = await rootBundle.load(key);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          final file = File('${destDir.path}/$leaf');
          await file.writeAsBytes(bytes, flush: true);
        }

        await _makeExecutable('${destDir.path}/surge');
        await _makeExecutable('${destDir.path}/aria2c');
        await marker.create();
      }

      final surge = File('${destDir.path}/surge');
      final aria = File('${destDir.path}/aria2c');
      if (await surge.exists()) surgePath = surge.path;
      if (await aria.exists()) aria2cPath = aria.path;
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
