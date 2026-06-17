import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Primary / ghost pill button with on-style hover and press feedback.
class GlassButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool busy;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.busy = false,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final primary = widget.primary;

    final Color textColor = primary
        ? const Color(0xFF06281D)
        : (enabled ? AppColors.foreground : AppColors.subtle);

    final BoxDecoration decoration = primary
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            gradient: const LinearGradient(
              colors: [Color(0xFF34D399), AppColors.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: _hovering ? 0.45 : 0.30),
                blurRadius: _hovering ? 22 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            color: _hovering
                ? AppColors.glassFillStrong
                : AppColors.glassFill,
            border: Border.all(
              color: _hovering ? AppColors.glassHighlight : AppColors.glassBorder,
            ),
          );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.55,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: 11),
              decoration: decoration,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.busy)
                    SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(textColor),
                      ),
                    )
                  else if (widget.icon != null)
                    Icon(widget.icon, size: 17, color: textColor),
                  if (widget.busy || widget.icon != null)
                    const SizedBox(width: AppSpacing.sm),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon-only action with a glass hover state and a tooltip.
class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.size = 38,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = widget.color ?? AppColors.foreground;
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: _hovering && enabled
                ? color.withValues(alpha: 0.14)
                : AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: _hovering && enabled
                  ? color.withValues(alpha: 0.32)
                  : AppColors.glassBorderSoft,
            ),
          ),
          child: Icon(
            widget.icon,
            size: widget.size * 0.46,
            color: enabled ? color : AppColors.subtle,
          ),
        ),
      ),
    );

    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}
