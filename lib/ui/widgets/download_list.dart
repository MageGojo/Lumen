import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../state/download_controller.dart';
import 'download_card.dart';
import 'empty_state.dart';

/// Scrollable list of download cards for the active filter, with empty states.
class DownloadList extends StatelessWidget {
  const DownloadList({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DownloadController>();
    final tasks = controller.tasks;

    if (tasks.isEmpty) {
      return _emptyFor(controller.filter);
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xl),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return DownloadCard(key: ValueKey(task.id), task: task);
      },
    );
  }

  Widget _emptyFor(DownloadFilter filter) {
    switch (filter) {
      case DownloadFilter.all:
        return const EmptyState(
          icon: Icons.cloud_download_rounded,
          title: '还没有下载任务',
          subtitle: '把链接粘贴到上方输入框,点击「添加」即可开始多线程下载。',
        );
      case DownloadFilter.active:
        return const EmptyState(
          icon: Icons.bolt_rounded,
          title: '没有进行中的任务',
          subtitle: '新添加的下载会出现在这里,实时显示速度与进度。',
        );
      case DownloadFilter.completed:
        return const EmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: '还没有完成的任务',
          subtitle: '下载完成的文件会归档到这里,可一键在 Finder 中查看。',
        );
      case DownloadFilter.failed:
        return const EmptyState(
          icon: Icons.verified_rounded,
          title: '没有失败的任务',
          subtitle: '一切正常 —— 暂时没有需要处理的错误。',
        );
    }
  }
}
