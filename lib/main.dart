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
    await Window.setEffect(effect: WindowEffect.hudWindow, dark: true);
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

  final home = Platform.environment['HOME'];
  final defaultDir = home == null ? null : '$home/Downloads';

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

  // Loopback bridge for the sideloaded browser extension.
  final bridge = LocalBridgeServer(
    port: settings.bridgePort,
    onAdd: (url, {referer, title, userAgent, headers}) async {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
      if (LinkClassifier.classify(url) == LinkRoute.share) {
        apiTools
          ..setApiKey(settings.apiKey)
          ..setBaseUrl(settings.parseBaseUrl);
        await apiTools.parseShareLink(url);
        final err = apiTools.videoError;
        return BridgeResult(err == null, err ?? '已解析,请在应用内选择清晰度下载');
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
