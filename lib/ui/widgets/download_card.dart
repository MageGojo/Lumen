import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/folder_picker.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/download_task.dart';
import '../../state/download_controller.dart';
import 'glass_button.dart';

typedef _FileVisual = ({IconData icon, Color color});

_FileVisual _fileVisual(String ext) {
  switch (ext) {
    case 'zip':
    case '7z':
    case 'rar':
    case 'tar':
    case 'gz':
    case 'bz2':
    case 'xz':
      return (icon: Icons.folder_zip_rounded, color: AppColors.warning);
    case 'apk':
      return (icon: Icons.android_rounded, color: AppColors.auroraEmerald);
    case 'dmg':
    case 'pkg':
    case 'iso':
      return (icon: Icons.album_rounded, color: AppColors.info);
    case 'exe':
    case 'msi':
      return (icon: Icons.terminal_rounded, color: AppColors.subtle);
    case 'mp4':
    case 'mkv':
    case 'mov':
    case 'avi':
    case 'webm':
    case 'flv':
      return (icon: Icons.movie_rounded, color: AppColors.auroraViolet);
    case 'mp3':
    case 'flac':
    case 'wav':
    case 'aac':
    case 'm4a':
      return (icon: Icons.music_note_rounded, color: Color(0xFFEC4899));
    case 'pdf':
      return (icon: Icons.picture_as_pdf_rounded, color: AppColors.destructive);
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'svg':
    case 'heic':
      return (icon: Icons.image_rounded, color: AppColors.auroraCyan);
    case 'doc':
    case 'docx':
    case 'txt':
    case 'md':
      return (icon: Icons.description_rounded, color: AppColors.info);
    default:
      return (icon: Icons.insert_drive_file_rounded, color: AppColors.muted);
  }
}

class DownloadCard extends StatefulWidget {
  final DownloadTask task;
  const DownloadCard({super.key, required this.task});

  @override
  State<DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<DownloadCard> {
  bool _hovering = false;

  Future<void> _confirmDelete() async {
    final controller = context.read<DownloadController>();
    final choice = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _DeleteDialog(filename: widget.task.filename),
    );
    if (choice == 'remove') {
      await controller.remove(widget.task.id);
    } else if (choice == 'purge') {
      await controller.remove(widget.task.id, purge: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final controller = context.read<DownloadController>();
    final statusColor = AppColors.statusColor(task.status);
    final visual = _fileVisual(task.extension);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? 1.004 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: GlassPanel(
          radius: AppRadii.lg,
          padding: const EdgeInsets.all(AppSpacing.md),
          shadows: _hovering ? AppShadows.lifted : AppShadows.soft,
          borderColor:
              _hovering ? AppColors.glassHighlight : AppColors.glassBorder,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconTile(icon: visual.icon, color: visual.color),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          task.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.foreground,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(task),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.subtle,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  _StatusPill(status: task.status, color: statusColor),
                  const SizedBox(width: AppSpacing.md),
                  ..._actions(controller, task),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _ProgressBar(
                fraction: task.status == DownloadStatus.completed
                    ? 1.0
                    : task.fraction,
                color: statusColor,
                active: task.status == DownloadStatus.downloading,
              ),
              const SizedBox(height: AppSpacing.sm),
              _MetaRow(task: task, statusColor: statusColor),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(DownloadTask task) {
    if (task.url.isNotEmpty) {
      final host = Uri.tryParse(task.url)?.host;
      if (host != null && host.isNotEmpty) return host;
      return task.url;
    }
    return task.destPath;
  }

  List<Widget> _actions(DownloadController controller, DownloadTask task) {
    final buttons = <Widget>[];
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        buttons.add(GlassIconButton(
          icon: Icons.pause_rounded,
          tooltip: '暂停',
          onPressed: () => controller.pause(task.id),
        ));
        break;
      case DownloadStatus.paused:
        buttons.add(GlassIconButton(
          icon: Icons.play_arrow_rounded,
          tooltip: '继续',
          color: AppColors.accent,
          onPressed: () => controller.resume(task.id),
        ));
        break;
      case DownloadStatus.error:
        buttons.add(GlassIconButton(
          icon: Icons.refresh_rounded,
          tooltip: '重试',
          color: AppColors.accent,
          onPressed: () => controller.resume(task.id),
        ));
        break;
      case DownloadStatus.completed:
        buttons.add(GlassIconButton(
          icon: Icons.folder_open_rounded,
          tooltip: '在 Finder 中显示',
          onPressed: task.destPath.isEmpty
              ? null
              : () => FinderReveal.reveal(task.destPath),
        ));
        break;
      case DownloadStatus.unknown:
        break;
    }
    buttons.add(const SizedBox(width: AppSpacing.sm));
    buttons.add(GlassIconButton(
      icon: Icons.delete_outline_rounded,
      tooltip: '删除',
      color: AppColors.destructive,
      onPressed: _confirmDelete,
    ));
    return buttons;
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconTile({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.26),
            color.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Icon(icon, size: 21, color: color),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final DownloadStatus status;
  final Color color;
  const _StatusPill({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            AppColors.statusLabel(status),
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double fraction;
  final Color color;
  final bool active;
  const _ProgressBar({
    required this.fraction,
    required this.color,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 7,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth * fraction.clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.glassFillStrong,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOut,
                  width: width,
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(color, Colors.white, 0.25) ?? color,
                        color,
                      ],
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final DownloadTask task;
  final Color statusColor;
  const _MetaRow({required this.task, required this.statusColor});

  @override
  Widget build(BuildContext context) {
    final sizeText = task.totalSize > 0
        ? '${Formatters.bytes(task.downloaded)} / ${Formatters.bytes(task.totalSize)}'
        : Formatters.bytes(task.downloaded);

    final right = <Widget>[];
    if (task.status == DownloadStatus.downloading) {
      right.add(_metaText(Formatters.speed(task.speedBytesPerSec),
          color: AppColors.accent, bold: true));
      if (task.etaSeconds > 0) {
        right.add(_dot());
        right.add(_metaText('剩余 ${Formatters.eta(task.etaSeconds)}'));
      }
      if (task.connections > 0) {
        right.add(_dot());
        right.add(_metaText('${task.connections} 连接'));
      }
    } else if (task.status == DownloadStatus.completed) {
      right.add(_metaText('完成', color: statusColor, bold: true));
      if (task.avgSpeedBps > 0) {
        right.add(_dot());
        right.add(_metaText('均速 ${Formatters.speed(task.avgSpeedBps)}'));
      }
    } else if (task.status == DownloadStatus.error) {
      right.add(_metaText('下载失败', color: AppColors.destructive, bold: true));
    } else if (task.status == DownloadStatus.paused) {
      right.add(_metaText('已暂停', color: AppColors.warning, bold: true));
    }

    return Row(
      children: [
        _metaText(sizeText),
        const SizedBox(width: AppSpacing.sm),
        _metaText('· ${Formatters.percent(task.progress)}',
            color: AppColors.subtle),
        const Spacer(),
        ...right,
      ],
    );
  }

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text('·', style: TextStyle(color: AppColors.subtle)),
      );

  Widget _metaText(String text, {Color? color, bool bold = false}) {
    return Text(
      text,
      style: TextStyle(
        color: color ?? AppColors.muted,
        fontSize: 12,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _DeleteDialog extends StatelessWidget {
  final String filename;
  const _DeleteDialog({required this.filename});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassPanel(
          radius: AppRadii.xl,
          blur: 28,
          fill: AppColors.surface.withValues(alpha: 0.7),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.destructive.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.destructive, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '删除任务',
                      style: TextStyle(
                        color: AppColors.foreground,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '“$filename”',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.foreground,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '可仅移除任务记录,或连同已下载的文件一起删除。',
                style: TextStyle(
                    color: AppColors.muted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  GlassButton(
                    label: '取消',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  GlassButton(
                    label: '仅移除记录',
                    onPressed: () => Navigator.of(context).pop('remove'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassButton(
                    label: '删除文件',
                    icon: Icons.delete_forever_rounded,
                    onPressed: () => Navigator.of(context).pop('purge'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
