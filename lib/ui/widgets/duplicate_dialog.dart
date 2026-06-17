import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/formatters.dart';
import '../../data/services/duplicate_detector.dart';

/// Shows the pre-download duplicate prompt. Resolves to the user's
/// [DuplicateDecision]; dismissing (tap outside / Esc) defaults to `cancel`.
Future<DuplicateDecision> showDuplicateDialog(
  BuildContext context,
  DuplicateReport report,
) async {
  final result = await showDialog<DuplicateDecision>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => _DuplicateDialog(report: report),
  );
  return result ?? DuplicateDecision.cancel;
}

class _DuplicateDialog extends StatelessWidget {
  final DuplicateReport report;
  const _DuplicateDialog({required this.report});

  ({String headline, String detail}) get _copy {
    if (report.hasIdentical) {
      return (
        headline: '下载目录已存在相同文件',
        detail: '存在同名且大小完全一致的文件,几乎可以确定是同一个文件,通常无需重复下载。',
      );
    }
    if (report.hasVersionConflict) {
      return (
        headline: '已存在同名文件',
        detail: report.sizeKnown
            ? '同名文件的大小不一样,很可能是不同版本或不同文件。若想同时保留,请选择「自动改名」。'
            : '已存在同名文件,但服务器未提供大小,无法确认是否为同一文件。',
      );
    }
    return (
      headline: '发现疑似重复文件',
      detail: '存在大小完全相同、但文件名不同的文件,疑似是改过名的副本。',
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    final remoteSize =
        report.sizeKnown ? Formatters.bytes(report.remoteSize) : '大小未知';
    final shown = report.matches.take(5).toList();
    final overflow = report.matches.length - shown.length;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassPanel(
          radius: AppRadii.xl,
          blur: 28,
          fill: AppColors.surface.withValues(alpha: 0.72),
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
                      color: AppColors.warning.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: const Icon(Icons.file_copy_rounded,
                        color: AppColors.warning, size: 21),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      copy.headline,
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
                copy.detail,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _IncomingRow(name: report.remoteName, size: remoteSize),
              const SizedBox(height: AppSpacing.md),
              Text(
                '目录中已有',
                style: TextStyle(
                  color: AppColors.subtle,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...shown.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _MatchRow(file: m),
                  )),
              if (overflow > 0)
                Text(
                  '…另有 $overflow 个',
                  style: TextStyle(color: AppColors.subtle, fontSize: 11.5),
                ),
              const SizedBox(height: AppSpacing.lg),
              _DecisionButton(
                icon: Icons.block_rounded,
                label: '取消(不下载)',
                hint: '推荐 · 默认',
                tone: _Tone.primary,
                onTap: () =>
                    Navigator.of(context).pop(DuplicateDecision.cancel),
              ),
              const SizedBox(height: AppSpacing.sm),
              _DecisionButton(
                icon: Icons.call_split_rounded,
                label: '仍要下载 · 自动改名保留两者',
                hint: '新文件加后缀,旧文件不动',
                tone: _Tone.neutral,
                onTap: () =>
                    Navigator.of(context).pop(DuplicateDecision.rename),
              ),
              const SizedBox(height: AppSpacing.sm),
              _DecisionButton(
                icon: Icons.delete_sweep_rounded,
                label: '替换 · 删除已存在文件再下载',
                hint: '会删掉上面列出的文件',
                tone: _Tone.destructive,
                onTap: () =>
                    Navigator.of(context).pop(DuplicateDecision.replace),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncomingRow extends StatelessWidget {
  final String name;
  final String size;
  const _IncomingRow({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.download_rounded, size: 17, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            size,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  final ExistingFile file;
  const _MatchRow({required this.file});

  ({String label, Color color}) get _badge {
    switch (file.kind) {
      case DuplicateMatchKind.identical:
        return (label: '完全相同', color: AppColors.destructive);
      case DuplicateMatchKind.sameNameDiffSize:
        return (label: '同名·大小不同', color: AppColors.warning);
      case DuplicateMatchKind.sameSizeDiffName:
        return (label: '同大小·已改名', color: AppColors.info);
    }
  }

  String _date(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badge;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  file.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  badge.label,
                  style: TextStyle(
                    color: badge.color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${Formatters.bytes(file.size)} · ${_date(file.modified)}',
            style: TextStyle(
              color: AppColors.subtle,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tone { primary, neutral, destructive }

class _DecisionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String hint;
  final _Tone tone;
  final VoidCallback onTap;

  const _DecisionButton({
    required this.icon,
    required this.label,
    required this.hint,
    required this.tone,
    required this.onTap,
  });

  @override
  State<_DecisionButton> createState() => _DecisionButtonState();
}

class _DecisionButtonState extends State<_DecisionButton> {
  bool _hovering = false;

  Color get _accent {
    switch (widget.tone) {
      case _Tone.primary:
        return AppColors.accent;
      case _Tone.neutral:
        return AppColors.foreground;
      case _Tone.destructive:
        return AppColors.destructive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    final accent = _accent;
    final bg = switch (tone) {
      _Tone.primary =>
        accent.withValues(alpha: _hovering ? 0.22 : 0.14),
      _Tone.destructive =>
        accent.withValues(alpha: _hovering ? 0.16 : 0.08),
      _Tone.neutral =>
        _hovering ? AppColors.glassFillStrong : AppColors.glassFill,
    };
    final border = switch (tone) {
      _Tone.primary => accent.withValues(alpha: 0.4),
      _Tone.destructive => accent.withValues(alpha: 0.32),
      _Tone.neutral =>
        _hovering ? AppColors.glassHighlight : AppColors.glassBorderSoft,
    };
    final iconColor = tone == _Tone.neutral ? AppColors.muted : accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: iconColor),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: AppColors.foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.hint,
                      style: TextStyle(
                        color: AppColors.subtle,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
