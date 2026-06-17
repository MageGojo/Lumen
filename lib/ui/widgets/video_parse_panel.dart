import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../data/models/video_parse.dart';
import '../../state/api_tools_controller.dart';
import '../../state/download_controller.dart';

/// Inline result of parsing a share link pasted into the download bar.
/// Self-hides when there is nothing to show.
class VideoParsePanel extends StatelessWidget {
  const VideoParsePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiToolsController>();
    if (!api.hasVideoActivity) return const SizedBox.shrink();

    final loading = api.isBusy(ApiToolKind.videoParse);
    final result = api.videoResult;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: GlassPanel(
        radius: AppRadii.xl,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _SectionLabel(
                  icon: Icons.movie_filter_rounded,
                  color: AppColors.auroraViolet,
                  label: '视频解析',
                ),
                if (result != null && result.platformLabel.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _Tag(text: result.platformLabel),
                ],
                if (result != null && result.type.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _Tag(text: result.type),
                ],
                const Spacer(),
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  )
                else
                  _CloseButton(onTap: context.read<ApiToolsController>().clearVideo),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (loading)
              const _LoadingLine(label: '正在后台解析链接…')
            else if (api.videoError != null)
              _ErrorLine(message: api.videoError!)
            else if (result != null)
              _ResultBody(result: result),
          ],
        ),
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  final VideoParseResult result;
  const _ResultBody({required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(url: result.coverUrl),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title.isEmpty ? '未命名内容' : result.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.foreground,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _meta(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (result.videoList.isNotEmpty)
          _QualityList(qualities: result.videoList)
        else if (result.videoUrl.isNotEmpty)
          _DownloadButton(
            label: '下载视频',
            url: result.bestVideoUrl,
            primary: true,
          ),
        if (result.imageList.isNotEmpty) ...[
          if (result.videoList.isNotEmpty || result.videoUrl.isNotEmpty)
            const SizedBox(height: AppSpacing.md),
          _ImageActions(images: result.imageList),
        ],
        if (result.audioUrl.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _DownloadButton(label: '下载音频', url: result.audioUrl),
        ],
      ],
    );
  }

  String _meta() {
    final parts = <String>[];
    if (result.authorName.isNotEmpty) parts.add('作者 ${result.authorName}');
    if (result.videoList.isNotEmpty) parts.add('${result.videoList.length} 种清晰度');
    if (result.imageList.isNotEmpty) parts.add('${result.imageList.length} 张图片');
    return parts.isEmpty ? '解析完成' : parts.join('  ·  ');
  }
}

class _QualityList extends StatelessWidget {
  final List<VideoQuality> qualities;
  const _QualityList({required this.qualities});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final q in qualities)
          if (q.hasUrl)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _QualityRow(quality: q),
            ),
      ],
    );
  }
}

class _QualityRow extends StatelessWidget {
  final VideoQuality quality;
  const _QualityRow({required this.quality});

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (quality.resolution.isNotEmpty) quality.resolution,
      if (quality.size.isNotEmpty) quality.size,
    ].join('  ·  ');

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundDeep.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quality.quality.isEmpty ? '默认清晰度' : quality.quality,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.subtle,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _DownloadButton(
            label: '下载',
            url: quality.url,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _ImageActions extends StatelessWidget {
  final List<String> images;
  const _ImageActions({required this.images});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '图文内容 · ${images.length} 张图片',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
        _DownloadButton(
          label: '下载全部图片',
          urls: images,
          primary: true,
        ),
      ],
    );
  }
}

class _DownloadButton extends StatefulWidget {
  final String label;
  final String? url;
  final List<String>? urls;
  final bool primary;
  final bool compact;

  const _DownloadButton({
    required this.label,
    this.url,
    this.urls,
    this.primary = false,
    this.compact = false,
  });

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    final targets = widget.urls ?? (widget.url == null ? const [] : [widget.url!]);
    if (targets.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<DownloadController>();
    setState(() => _busy = true);

    var added = 0;
    String? lastError;
    for (final t in targets) {
      final error = await controller.addUrl(t);
      if (error == null) {
        added++;
      } else {
        lastError = error;
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);

    final ok = added > 0;
    final text = ok
        ? (targets.length > 1 ? '已加入 $added 个下载任务' : '已加入下载队列')
        : (lastError ?? '加入下载失败');
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface.withValues(alpha: 0.96),
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            side: BorderSide(
              color: (ok ? AppColors.accent : AppColors.destructive)
                  .withValues(alpha: 0.5),
            ),
          ),
          content: Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_rounded,
                color: ok ? AppColors.accent : AppColors.destructive,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: AppColors.foreground),
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.select<DownloadController, bool>(
      (c) => c.isConnected,
    );
    final enabled = connected && !_busy;
    final bg = widget.primary
        ? AppColors.accent.withValues(alpha: enabled ? 0.16 : 0.06)
        : AppColors.glassFill;
    final border = widget.primary
        ? AppColors.accent.withValues(alpha: enabled ? 0.32 : 0.12)
        : AppColors.glassBorderSoft;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? _run : null,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 12 : AppSpacing.md,
            vertical: widget.compact ? 7 : 9,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.accent),
                  ),
                )
              else
                Icon(
                  Icons.download_rounded,
                  size: 15,
                  color: enabled ? AppColors.accent : AppColors.subtle,
                ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: enabled ? AppColors.foreground : AppColors.subtle,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final String url;
  const _Cover({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        width: 120,
        height: 72,
        color: AppColors.backgroundDeep.withValues(alpha: 0.5),
        child: url.isEmpty
            ? Icon(Icons.image_rounded,
                color: AppColors.subtle, size: 22)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.broken_image_rounded,
                  color: AppColors.subtle,
                  size: 22,
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _SectionLabel({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: color.withValues(alpha: 0.24)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(
            color: AppColors.foreground,
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: AppColors.glassBorderSoft),
          ),
          child: Icon(Icons.close_rounded,
              size: 15, color: AppColors.muted),
        ),
      ),
    );
  }
}

class _LoadingLine extends StatelessWidget {
  final String label;
  const _LoadingLine({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(AppColors.accent),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  final String message;
  const _ErrorLine({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 16, color: AppColors.warning),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.warning, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}
