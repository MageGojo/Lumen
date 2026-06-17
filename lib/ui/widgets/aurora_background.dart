import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Slowly drifting colored light blobs over a deep gradient. Sits behind the
/// frosted-glass layers to give them something rich to blur.
class AuroraBackground extends StatefulWidget {
  final bool animate;
  const AuroraBackground({super.key, this.animate = true});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 26));
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        final isDark = AppColors.active.brightness == Brightness.dark;

        // In light mode the aurora is a set of cool, icy tints (blue / cyan /
        // violet) so the frosted panels refract a clean, high-tech glow while
        // the canvas stays a crisp modern white.
        final Color cViolet =
            isDark ? AppColors.auroraViolet : const Color(0xFFCABEF8);
        final Color cCyan =
            isDark ? AppColors.auroraCyan : const Color(0xFFAEE0F7);
        final Color cEmerald =
            isDark ? AppColors.auroraEmerald : const Color(0xFFB6E8F0);
        final Color cBlue =
            isDark ? AppColors.auroraBlue : const Color(0xFFB3CBF8);

        final double oViolet = isDark ? 0.30 : 0.34;
        final double oCyan = isDark ? 0.26 : 0.32;
        final double oEmerald = isDark ? 0.22 : 0.26;
        final double oBlue = isDark ? 0.20 : 0.30;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.background, AppColors.backgroundDeep],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _blob(
                Alignment(-0.85 + 0.18 * math.sin(t), -0.7 + 0.12 * math.cos(t)),
                cViolet,
                isDark ? 540 : 680,
                oViolet,
              ),
              _blob(
                Alignment(
                    0.95 + 0.10 * math.cos(t * 0.8), -0.55 + 0.18 * math.sin(t * 1.1)),
                cCyan,
                isDark ? 500 : 640,
                oCyan,
              ),
              _blob(
                Alignment(
                    0.2 + 0.22 * math.sin(t * 0.6), 0.95 + 0.08 * math.cos(t)),
                cEmerald,
                isDark ? 580 : 720,
                oEmerald,
              ),
              _blob(
                Alignment(
                    -0.6 + 0.14 * math.cos(t * 1.3), 0.7 + 0.12 * math.sin(t * 0.9)),
                cBlue,
                isDark ? 460 : 620,
                oBlue,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.25,
                    colors: [
                      Colors.transparent,
                      AppColors.backgroundDeep.withValues(
                        alpha: isDark ? 0.38 : 0.16,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _blob(Alignment alignment, Color color, double size, double opacity) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
