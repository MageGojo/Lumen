import 'package:flutter/material.dart';

import '../../data/models/download_task.dart';

/// A swappable set of neutral + glass tokens for light / dark theming.
/// Accent and status colors are stable across themes (see [AppColors]).
class AppPalette {
  final Brightness brightness;
  final Color background;
  final Color backgroundDeep;
  final Color surface;
  final Color foreground;
  final Color muted;
  final Color subtle;

  /// Base fill for large frosted panels (cards).
  final Color panelFill;

  /// Fill for small controls (inputs / chips) that sit on top of panels.
  final Color glassFill;
  final Color glassFillStrong;
  final Color glassHighlight;
  final Color glassBorder;
  final Color glassBorderSoft;

  /// Bright specular sheen painted across the top edge of a glass surface.
  final Color glassSheen;

  /// Bright "lit" edge of the glass rim (top-left), where light catches.
  final Color glassRimLight;

  /// Soft shaded edge of the glass rim (bottom-right), giving thickness.
  final Color glassRimShadow;

  const AppPalette({
    required this.brightness,
    required this.background,
    required this.backgroundDeep,
    required this.surface,
    required this.foreground,
    required this.muted,
    required this.subtle,
    required this.panelFill,
    required this.glassFill,
    required this.glassFillStrong,
    required this.glassHighlight,
    required this.glassBorder,
    required this.glassBorderSoft,
    required this.glassSheen,
    required this.glassRimLight,
    required this.glassRimShadow,
  });
}

const AppPalette _darkPalette = AppPalette(
  brightness: Brightness.dark,
  background: Color(0xFF0F172A),
  backgroundDeep: Color(0xFF0B1120),
  surface: Color(0xFF10192E),
  foreground: Color(0xFFF8FAFC),
  muted: Color(0xFF94A3B8),
  subtle: Color(0xFF64748B),
  panelFill: Color(0x12FFFFFF),
  glassFill: Color(0x0EFFFFFF),
  glassFillStrong: Color(0x1AFFFFFF),
  glassHighlight: Color(0x29FFFFFF),
  glassBorder: Color(0x1FFFFFFF),
  glassBorderSoft: Color(0x12FFFFFF),
  glassSheen: Color(0x16FFFFFF),
  glassRimLight: Color(0x3DFFFFFF),
  glassRimShadow: Color(0x26000000),
);

/// Modern, high-tech light theme: a crisp cool white (no warm/yellow cast),
/// cool slate ink, and a strongly translucent glass body lit by cool
/// blue/cyan/violet refraction behind the frosted panels (liquid-glass feel).
const AppPalette _lightPalette = AppPalette(
  brightness: Brightness.light,
  // A soft cool-gray "desk" — slightly deeper than the panels so the frosted
  // glass can float above it with real depth (not a flat white-on-white wash).
  background: Color(0xFFE7EDF6),
  backgroundDeep: Color(0xFFD3DDEC),
  surface: Color(0xFFFFFFFF),
  // Cool slate-black ink for high-contrast, readable text.
  foreground: Color(0xFF0B1424),
  muted: Color(0xFF54607A),
  subtle: Color(0xFF8893AB),
  // Frosted-glass body: mostly opaque white so content stays crisp, with just
  // enough translucency for the blur + cool tint to read as real glass.
  panelFill: Color(0xD6FFFFFF),
  // Cool slate tints/borders sit crisply on the white cards.
  glassFill: Color(0x100B1A33),
  glassFillStrong: Color(0x1C0B1A33),
  glassHighlight: Color(0x2E0B1A33),
  glassBorder: Color(0x220B1A33),
  glassBorderSoft: Color(0x140B1A33),
  // Restrained specular highlights — a soft top gleam + a defined cool edge,
  // not a glare.
  glassSheen: Color(0x7AFFFFFF),
  glassRimLight: Color(0xD6FFFFFF),
  glassRimShadow: Color(0x260B1A33),
);

/// Design tokens. Neutral / glass tokens follow the active [AppPalette];
/// accent + status colors are constant across themes.
class AppColors {
  AppColors._();

  /// The active palette; swapped by [SurgeGlassApp] on theme change.
  static AppPalette active = _darkPalette;

  static AppPalette get darkPalette => _darkPalette;
  static AppPalette get lightPalette => _lightPalette;

  // Theme-dependent neutrals.
  static Color get background => active.background;
  static Color get backgroundDeep => active.backgroundDeep;
  static Color get surface => active.surface;
  static Color get foreground => active.foreground;
  static Color get muted => active.muted;
  static Color get subtle => active.subtle;

  // Theme-dependent glass surfaces.
  static Color get panelFill => active.panelFill;
  static Color get glassFill => active.glassFill;
  static Color get glassFillStrong => active.glassFillStrong;
  static Color get glassHighlight => active.glassHighlight;
  static Color get glassBorder => active.glassBorder;
  static Color get glassBorderSoft => active.glassBorderSoft;
  static Color get glassSheen => active.glassSheen;
  static Color get glassRimLight => active.glassRimLight;
  static Color get glassRimShadow => active.glassRimShadow;

  // Stable accents / status colors (identical in both themes).
  static const Color primary = Color(0xFF1E3A5F);
  static const Color accent = Color(0xFF10B981);
  static const Color accentDim = Color(0xFF059669);
  static const Color destructive = Color(0xFFF43F5E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF38BDF8);

  static const Color auroraCyan = Color(0xFF22D3EE);
  static const Color auroraViolet = Color(0xFF8B5CF6);
  static const Color auroraEmerald = Color(0xFF10B981);
  static const Color auroraBlue = Color(0xFF3B82F6);

  static Color statusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return accent;
      case DownloadStatus.queued:
        return info;
      case DownloadStatus.paused:
        return warning;
      case DownloadStatus.completed:
        return auroraBlue;
      case DownloadStatus.error:
        return destructive;
      case DownloadStatus.unknown:
        return subtle;
    }
  }

  static String statusLabel(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return '下载中';
      case DownloadStatus.queued:
        return '排队中';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.error:
        return '失败';
      case DownloadStatus.unknown:
        return '未知';
    }
  }
}

/// 4 / 8 spacing rhythm.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadii {
  AppRadii._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;
}

class AppShadows {
  AppShadows._();

  static bool get _dark => AppColors.active.brightness == Brightness.dark;

  /// Two-layer shadow (broad ambient + tight contact) so glass panels appear
  /// to float above the background instead of sitting flat on it.
  static List<BoxShadow> get soft => [
        BoxShadow(
          color: Colors.black.withValues(alpha: _dark ? 0.34 : 0.10),
          blurRadius: 34,
          offset: const Offset(0, 18),
          spreadRadius: -12,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: _dark ? 0.20 : 0.05),
          blurRadius: 10,
          offset: const Offset(0, 3),
          spreadRadius: -6,
        ),
      ];

  static List<BoxShadow> get lifted => [
        BoxShadow(
          color: Colors.black.withValues(alpha: _dark ? 0.44 : 0.16),
          blurRadius: 52,
          offset: const Offset(0, 28),
          spreadRadius: -14,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: _dark ? 0.24 : 0.07),
          blurRadius: 14,
          offset: const Offset(0, 5),
          spreadRadius: -6,
        ),
      ];
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() => _build(_darkPalette);
  static ThemeData light() => _build(_lightPalette);

  static ThemeData _build(AppPalette p) {
    final isDark = p.brightness == Brightness.dark;
    final scheme = isDark
        ? ColorScheme.dark(
            primary: AppColors.accent,
            onPrimary: const Color(0xFF06281D),
            secondary: AppColors.info,
            surface: p.surface,
            onSurface: p.foreground,
            error: AppColors.destructive,
          )
        : ColorScheme.light(
            primary: AppColors.accentDim,
            onPrimary: Colors.white,
            secondary: AppColors.info,
            surface: p.surface,
            onSurface: p.foreground,
            error: AppColors.destructive,
          );

    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      fontFamily: '.AppleSystemUIFont',
      splashFactory: InkSparkle.splashFactory,
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.backgroundDeep.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: p.glassBorder),
        ),
        textStyle: TextStyle(color: p.foreground, fontSize: 12),
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: p.foreground,
        displayColor: p.foreground,
      ),
    );
  }
}
