import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/utils/link_classifier.dart';
import 'core/utils/native_binaries.dart';
import 'data/repository/download_repository.dart';
import 'data/services/duplicate_detector.dart';
import 'data/services/local_bridge_server.dart';
import 'state/api_tools_controller.dart';
import 'state/download_controller.dart';
import 'state/settings_controller.dart';
import 'ui/widgets/duplicate_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Native macOS vibrancy + a frameless, draggable window.
  await Window.initialize();
  await windowManager.ensureInitialized();

  try {
    // hudWindow is macOS-only; Windows gets acrylic. Either way the painted
    // aurora background is the fallback when the native effect is unavailable.
    await Window.setEffect(
      effect:
          Platform.isWindows ? WindowEffect.acrylic : WindowEffect.hudWindow,
      dark: true,
    );
  } catch (_) {
    // Vibrancy is a progressive enhancement; the painted aurora still works.
  }

  const windowOptions = WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(940, 640),
    center: true,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
    title: 'Lumen',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Unpack the bundled surge / aria2c engines before booting the daemon so the
  // locators can prefer them over any Homebrew install.
  await NativeBinaries.ensureExtracted();

  final String? defaultDir;
  if (Platform.isWindows) {
    final profile = Platform.environment['USERPROFILE'];
    defaultDir =
        (profile != null && profile.isNotEmpty) ? '$profile\\Downloads' : null;
  } else {
    final home = Platform.environment['HOME'];
    defaultDir = home != null ? '$home/Downloads' : null;
  }

  final settings = SettingsController();
  await settings.load();

  final apiTools = ApiToolsController()
    ..setBaseUrl(settings.parseBaseUrl)
    ..setApiKey(settings.apiKey);

  final downloads = DownloadController(DownloadRepository())
    ..setDefaultOutputDir(defaultDir)
    ..setDownloadHeaders(
      userAgent: settings.userAgent,
      headers: settings.customHeaders,
    );
  downloads.bootstrap();

  // Keep the engines' default UA / request headers in lockstep with settings.
  settings.addListener(() {
    downloads.setDownloadHeaders(
      userAgent: settings.userAgent,
      headers: settings.customHeaders,
    );
  });

  // Lets the loopback bridge raise the duplicate prompt over the running app.
  final navigatorKey = GlobalKey<NavigatorState>();

  // Bring the window to the front, but at most once every few seconds. A plain
  // download hand-off no longer raises the window at all (it stays silent and
  // never steals focus); this is only used where the user must actually see the
  // app — a parsed share link or a duplicate prompt — and the throttle stops a
  // burst of bridge calls from turning into a window-popping storm.
  var lastRaiseAt = 0;
  // Synchronous + fire-and-forget so callers never open an async gap before
  // touching a BuildContext (and a window raise needn't block the hand-off).
  void raiseWindow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastRaiseAt < 3000) return;
    lastRaiseAt = now;
    () async {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    }();
  }

  // Desktop-side coalescing for the bridge: a page (or the extension after its
  // MV3 worker restarts and loses its own de-dupe) can fire the same download
  // repeatedly. Acknowledge an identical URL seen within this window without
  // re-running the HEAD probe + directory scan + re-add, so a burst can't pile
  // blocking work onto the UI isolate.
  final recentAdds = <String, int>{};
  bool addedRecently(String url) {
    final now = DateTime.now().millisecondsSinceEpoch;
    recentAdds.removeWhere((_, t) => now - t > 5000);
    if (recentAdds.containsKey(url)) return true;
    recentAdds[url] = now;
    return false;
  }

  // Loopback bridge for the sideloaded browser extension.
  final bridge = LocalBridgeServer(
    port: settings.bridgePort,
    onAdd: (url, {referer, title, userAgent, headers}) async {
      if (LinkClassifier.classify(url) == LinkRoute.share) {
        raiseWindow();
        apiTools
          ..setApiKey(settings.apiKey)
          ..setBaseUrl(settings.parseBaseUrl);
        await apiTools.parseShareLink(url);
        final err = apiTools.videoError;
        return BridgeResult(err == null, err ?? '已解析,请在应用内选择清晰度下载');
      }
      // Coalesce a burst of identical add requests (see addedRecently) so the
      // same URL fired repeatedly doesn't re-probe + re-scan + re-queue.
      if (addedRecently(url)) {
        return const BridgeResult(true, '已在下载队列(忽略重复请求)');
      }
      // Only run the duplicate prompt when a UI surface is actually available;
      // otherwise fall back to a normal add so extension downloads never get
      // silently dropped.
      final hasUi = navigatorKey.currentState?.overlay != null;
      final outcome = await downloads.addWithDuplicateCheck(
        url,
        referer: referer,
        userAgent: userAgent,
        headers: headers,
        checkEnabled: settings.duplicateCheckEnabled && hasUi,
        onDuplicate: (report) async {
          raiseWindow();
          final ctx = navigatorKey.currentState?.overlay?.context;
          if (ctx == null) return DuplicateDecision.cancel;
          return showDuplicateDialog(ctx, report);
        },
      );
      if (outcome.cancelled) {
        return const BridgeResult(false, '检测到目录已存在该文件,已取消下载');
      }
      return BridgeResult(outcome.ok, outcome.ok ? '已加入下载队列' : (outcome.error ?? '添加失败'));
    },
  );
  await bridge.start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<DownloadController>.value(value: downloads),
        ChangeNotifierProvider<ApiToolsController>.value(value: apiTools),
      ],
      child: LumenApp(navigatorKey: navigatorKey),
    ),
  );
}
