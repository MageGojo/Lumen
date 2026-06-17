import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A reusable liquid-glass surface. Layers, from back to front:
///   1. a two-step drop shadow so the panel floats;
///   2. a gradient *rim* (bright top-left, shaded bottom-right) for thickness;
///   3. a backdrop blur that frosts whatever sits behind it;
///   4. a translucent body gradient with gentle top-left lensing;
///   5. a bright specular sheen across the top edge.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color? fill;
  final Color? borderColor;
  final List<BoxShadow>? shadows;
  final bool highlight;

  const GlassPanel({
    super.key,
    required this.child,
    this.radius = AppRadii.lg,
    this.blur = 26,
    this.padding,
    this.fill,
    this.borderColor,
    this.shadows,
    this.highlight = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final baseFill = fill ?? AppColors.panelFill;
    final isDark = AppColors.active.brightness == Brightness.dark;

    // The rim reads as the polished edge of the glass. A custom [borderColor]
    // (e.g. a hover state) tints the whole rim while keeping a lit top-left.
    const rimWidth = 1.2;
    final List<Color> rimColors = borderColor != null
        ? [
            Color.lerp(borderColor!, AppColors.glassRimLight, 0.55) ??
                borderColor!,
            borderColor!,
            borderColor!,
          ]
        : [
            AppColors.glassRimLight,
            AppColors.glassBorder,
            AppColors.glassRimShadow,
          ];

    final innerRadius = BorderRadius.circular(math.max(0, radius - rimWidth));

    // Body gradient: a touch brighter at the top-left, slightly deeper at the
    // bottom-right, to suggest light passing through a curved glass slab.
    final bodyTop =
        Color.lerp(baseFill, Colors.white, isDark ? 0.05 : 0.10) ?? baseFill;
    final bodyBottom =
        Color.lerp(baseFill, Colors.black, isDark ? 0.07 : 0.03) ?? baseFill;

    Widget glassBody = ClipRRect(
      borderRadius: innerRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: innerRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: highlight ? [bodyTop, baseFill, bodyBottom] : [baseFill, baseFill],
              stops: highlight ? const [0.0, 0.55, 1.0] : const [0.0, 1.0],
            ),
          ),
          foregroundDecoration: highlight
              ? BoxDecoration(
                  borderRadius: innerRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.glassSheen, const Color(0x00FFFFFF)],
                    stops: const [0.0, 0.16],
                  ),
                )
              : null,
          child: child,
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadows ?? AppShadows.soft,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: rimColors,
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        padding: const EdgeInsets.all(rimWidth),
        child: glassBody,
      ),
    );
  }
}

/// Glass surface that responds to hover/press with subtle elevation and
/// highlight, used for interactive cards and rows.
class GlassTappable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color? fill;
  final Color? borderColor;

  const GlassTappable({
    super.key,
    required this.child,
    this.onTap,
    this.radius = AppRadii.lg,
    this.blur = 26,
    this.padding,
    this.fill,
    this.borderColor,
  });

  @override
  State<GlassTappable> createState() => _GlassTappableState();
}

class _GlassTappableState extends State<GlassTappable> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final fill = _hovering ? AppColors.glassFillStrong : widget.fill;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering && widget.onTap != null ? 1.006 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: GlassPanel(
            radius: widget.radius,
            blur: widget.blur,
            padding: widget.padding,
            fill: fill,
            borderColor: _hovering ? AppColors.glassHighlight : widget.borderColor,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
