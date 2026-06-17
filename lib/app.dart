import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'state/settings_controller.dart';
import 'ui/home_page.dart';

class LumenApp extends StatelessWidget {
  /// Lets non-widget code (the loopback bridge) surface dialogs over the app.
  final GlobalKey<NavigatorState>? navigatorKey;

  const LumenApp({super.key, this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<SettingsController>().themeMode;
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };

    // Keep the global palette in lockstep with the rendered ThemeData so the
    // custom-painted glass UI matches.
    AppColors.active =
        brightness == Brightness.light ? AppColors.lightPalette : AppColors.darkPalette;
    final theme =
        brightness == Brightness.light ? AppTheme.light() : AppTheme.dark();

    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: theme,
      home: const HomePage(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clamped),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
