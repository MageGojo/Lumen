import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/glass.dart';
import '../core/utils/url_opener.dart';
import '../data/models/download_task.dart';
import '../state/download_controller.dart';
import 'settings_page.dart';
import 'widgets/add_download_bar.dart';
import 'widgets/api_insights_panel.dart';
import 'widgets/aurora_background.dart';
import 'widgets/download_list.dart';
import 'widgets/glass_button.dart';
import 'widgets/sidebar.dart';
import 'widgets/speed_limit_dialog.dart';
import 'widgets/title_bar.dart';
import 'widgets/video_parse_panel.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DownloadController>();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: AuroraBackground(animate: !reduceMotion)),
          Column(
            children: [
              TitleBar(trailing: _TitleBarActions(controller: controller)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: controller.isConnected
                      ? const _ConnectedBody(key: ValueKey('body'))
                      : _StatusView(
                          key: const ValueKey('status'),
                          controller: controller,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectedBody extends StatelessWidget {
  const _ConnectedBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Sidebar(),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              children: const [
                AddDownloadBar(),
                SizedBox(height: AppSpacing.lg),
                VideoParsePanel(),
                ApiInsightsPanel(),
                SizedBox(height: AppSpacing.lg),
                _ContentHeader(),
                SizedBox(height: AppSpacing.md),
                Expanded(child: DownloadList()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentHeader extends StatelessWidget {
  const _ContentHeader();

  String _title(DownloadFilter filter) {
    switch (filter) {
      case DownloadFilter.all:
        return '全部任务';
      case DownloadFilter.active:
        return '进行中';
      case DownloadFilter.completed:
        return '已完成';
      case DownloadFilter.failed:
        return '失败';
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DownloadController>();
    final tasks = controller.allTasks;
    final hasDownloading = tasks.any(
      (t) => t.status == DownloadStatus.downloading,
    );
    final hasPaused = tasks.any((t) => t.status == DownloadStatus.paused);
    final hasCompleted = controller.countCompleted > 0;
    final count = controller.tasks.length;

    return Row(
      children: [
        Text(
          _title(controller.filter),
          style: TextStyle(
            color: AppColors.foreground,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.glassBorderSoft),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (controller.allTasks.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          const _SortControl(),
        ],
        const Spacer(),
        if (hasPaused) ...[
          GlassButton(
            label: '全部继续',
            icon: Icons.play_arrow_rounded,
            onPressed: controller.resumeAll,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        if (hasDownloading) ...[
          GlassButton(
            label: '全部暂停',
            icon: Icons.pause_rounded,
            onPressed: controller.pauseAll,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        if (hasCompleted)
          GlassButton(
            label: '清除已完成',
            icon: Icons.cleaning_services_rounded,
            onPressed: controller.clean,
          ),
      ],
    );
  }
}

/// A glass pill that opens a popup to choose how the task list is ordered.
class _SortControl extends StatelessWidget {
  const _SortControl();

  String _label(DownloadSort sort) {
    switch (sort) {
      case DownloadSort.addedDesc:
        return '最新下载';
      case DownloadSort.nameAsc:
        return '名称 A→Z';
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DownloadController>();
    final current = controller.sort;

    return PopupMenuButton<DownloadSort>(
      tooltip: '排序方式',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 6),
      color: AppColors.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: AppColors.glassBorderSoft),
      ),
      onSelected: controller.setSort,
      itemBuilder: (context) => [
        _item(
          DownloadSort.addedDesc,
          Icons.schedule_rounded,
          '最新下载时间',
          current,
        ),
        _item(
          DownloadSort.nameAsc,
          Icons.sort_by_alpha_rounded,
          '名称(首字母)',
          current,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: AppColors.glassBorderSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 15, color: AppColors.muted),
            const SizedBox(width: 6),
            Text(
              _label(current),
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<DownloadSort> _item(
    DownloadSort value,
    IconData icon,
    String label,
    DownloadSort current,
  ) {
    final selected = value == current;
    return PopupMenuItem<DownloadSort>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: selected ? AppColors.accent : AppColors.muted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.foreground : AppColors.muted,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: AppSpacing.md),
            Icon(Icons.check_rounded, size: 16, color: AppColors.accent),
          ],
        ],
      ),
    );
  }
}

class _TitleBarActions extends StatelessWidget {
  final DownloadController controller;
  const _TitleBarActions({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ConnectionChip(controller: controller),
        const SizedBox(width: AppSpacing.sm),
        GlassIconButton(
          icon: Icons.api_rounded,
          tooltip: 'Apizero 官网',
          onPressed: () {
            UrlOpener.open('https://apizero.cn/aidocs');
          },
        ),
        const SizedBox(width: AppSpacing.sm),
        GlassIconButton(
          icon: Icons.settings_rounded,
          tooltip: '设置',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsPage(),
              ),
            );
          },
        ),
        const SizedBox(width: AppSpacing.sm),
        GlassIconButton(
          icon: Icons.speed_rounded,
          tooltip: '全局限速',
          onPressed: controller.isConnected
              ? () => showSpeedLimitDialog(context)
              : null,
        ),
      ],
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  final DownloadController controller;
  const _ConnectionChip({required this.controller});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    switch (controller.connection) {
      case DaemonConnection.connected:
        color = AppColors.accent;
        label = '已连接';
        break;
      case DaemonConnection.connecting:
        color = AppColors.warning;
        label = '连接中';
        break;
      case DaemonConnection.error:
        color = AppColors.destructive;
        label = '已断开';
        break;
      case DaemonConnection.notInstalled:
        color = AppColors.destructive;
        label = '未安装';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  final DownloadController controller;
  const _StatusView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final connecting = controller.connection == DaemonConnection.connecting;
    final notInstalled = controller.connection == DaemonConnection.notInstalled;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassPanel(
          radius: AppRadii.xl,
          blur: 24,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (connecting)
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(AppColors.accent),
                  ),
                )
              else
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.destructive.withValues(alpha: 0.14),
                  ),
                  child: Icon(
                    notInstalled
                        ? Icons.extension_off_rounded
                        : Icons.cloud_off_rounded,
                    color: AppColors.destructive,
                    size: 30,
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                connecting
                    ? '正在连接下载引擎…'
                    : (notInstalled ? '下载引擎未就绪' : '连接已断开'),
                style: TextStyle(
                  color: AppColors.foreground,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (controller.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  controller.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
              if (notInstalled && !Platform.isWindows) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundDeep.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.glassBorderSoft),
                  ),
                  child: const SelectableText(
                    'brew install surge',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontFamily: 'Menlo',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (!connecting) ...[
                const SizedBox(height: AppSpacing.xl),
                GlassButton(
                  label: '重试',
                  icon: Icons.refresh_rounded,
                  primary: true,
                  onPressed: controller.retry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
