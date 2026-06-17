import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_theme.dart';

/// Custom frameless, draggable title bar. Leaves room on the left for the
/// native macOS traffic-light controls.
class TitleBar extends StatelessWidget {
  final Widget? trailing;
  const TitleBar({super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: DragToMoveArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 82, right: AppSpacing.lg),
          child: Row(
            children: [
              const _BrandMark(),
              const SizedBox(width: AppSpacing.md),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Lumen',
                    style: TextStyle(
                      color: AppColors.foreground,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    '多线程下载 · Surge + aria2 双引擎',
                    style: TextStyle(
                      color: AppColors.muted.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        gradient: const LinearGradient(
          colors: [AppColors.auroraCyan, AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(
        Icons.light_mode_rounded,
        size: 20,
        color: Color(0xFF06281D),
      ),
    );
  }
}
