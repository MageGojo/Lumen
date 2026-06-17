import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;

/// Materializes the bundled browser extension to a stable folder and offers
/// the closest-to-one-click install paths Chrome's security model allows.
class ExtensionInstaller {
  ExtensionInstaller._();

  static const _assetPrefix = 'browser_extension/';

  static String get targetDir {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return '$home/Library/Application Support/surge_glass/browser_extension';
  }

  /// Copies the bundled extension out of the app and returns its folder path.
  ///
  /// Every file under `browser_extension/` is enumerated from the asset
  /// manifest (so new files like `content.js` are always included), and the
  /// folder is rebuilt from scratch so removed files don't linger and break
  /// the load.
  static Future<String> materialize() async {
    final dir = Directory(targetDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys =
        manifest.listAssets().where((k) => k.startsWith(_assetPrefix));
    for (final key in keys) {
      final rel = key.substring(_assetPrefix.length);
      if (rel.isEmpty) continue;
      try {
        final data = await rootBundle.load(key);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final file = File('${dir.path}/$rel');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // Skip any file that fails to load.
      }
    }
    return dir.path;
  }

  /// Opens chrome://extensions in Chrome (falls back to Edge).
  static Future<void> openExtensionsPage() async {
    final chrome = await Process.run(
      'open',
      ['-a', 'Google Chrome', 'chrome://extensions/'],
    );
    if (chrome.exitCode != 0) {
      await Process.run('open', ['-a', 'Microsoft Edge', 'edge://extensions/']);
    }
  }

  static Future<void> revealInFinder(String path) async {
    await Process.run('open', [path]);
  }

  /// Truly one-click: launches a fresh Chrome window with the extension
  /// already loaded (uses a dedicated profile so it works even if Chrome
  /// is already running).
  static Future<bool> launchChromeWithExtension(String extDir) async {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final profile =
        '$home/Library/Application Support/surge_glass/chrome-profile';
    await Directory(profile).create(recursive: true);
    try {
      final result = await Process.run('open', [
        '-na',
        'Google Chrome',
        '--args',
        '--load-extension=$extDir',
        '--user-data-dir=$profile',
        'chrome://extensions/',
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
