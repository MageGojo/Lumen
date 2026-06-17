import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/formatters.dart';
import '../../state/download_controller.dart';

/// Left navigation: category filters + a live global throughput card.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DownloadController>();

    return SizedBox(
      width: 230,
      child: GlassPanel(
        radius: AppRadii.xl,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.md),
              child: Text(
                '任务',
                style: TextStyle(
                  color: AppColors.subtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            _NavItem(
              filter: DownloadFilter.all,
              icon: Icons.dns_rounded,
              label: '全部',
            ),
            _NavItem(
              filter: DownloadFilter.active,
              icon: Icons.downloading_rounded,
              label: '进行中',
            ),
            _NavItem(
              filter: DownloadFilter.completed,
              icon: Icons.check_circle_rounded,
              label: '已完成',
            ),
            _NavItem(
              filter: DownloadFilter.failed,
              icon: Icons.error_rounded,
              label: '失败',
            ),
            const Spacer(),
            _GlobalSpeedCard(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final DownloadFilter filter;
  final IconData icon;
  final String label;

  const _NavItem({
    required this.filter,
    required this.icon,
    required this.label,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DownloadController>();
    final active = controller.filter == widget.filter;
    final count = controller.countFor(widget.filter);

    final Color fg = active ? AppColors.accent : AppColors.muted;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => controller.setFilter(widget.filter),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 11),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.14)
                  : (_hovering
                      ? AppColors.glassFill
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: active
                    ? AppColors.accent.withValues(alpha: 0.30)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: fg),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: active ? AppColors.foreground : AppColors.muted,
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.accent.withValues(alpha: 0.22)
                          : AppColors.glassFill,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: active ? AppColors.accent : AppColors.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalSpeedCard extends StatelessWidget {
  final DownloadController controller;
  const _GlobalSpeedCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final speed = controller.totalSpeedBytesPerSec;
    final active = controller.countDownloading;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.16),
            AppColors.auroraCyan.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.speed_rounded,
                size: 15,
                color: AppColors.accent.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Text(
                '当前总速度',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            Formatters.speed(speed),
            style: TextStyle(
              color: AppColors.foreground,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            active > 0 ? '$active 个任务下载中' : '暂无活动任务',
            style: TextStyle(
              color: AppColors.subtle,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
