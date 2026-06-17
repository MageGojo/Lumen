import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../state/download_controller.dart';
import 'glass_button.dart';

Future<void> showSpeedLimitDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => ChangeNotifierProvider<DownloadController>.value(
      value: context.read<DownloadController>(),
      child: const _SpeedLimitDialog(),
    ),
  );
}

class _SpeedLimitDialog extends StatefulWidget {
  const _SpeedLimitDialog();

  @override
  State<_SpeedLimitDialog> createState() => _SpeedLimitDialogState();
}

class _SpeedLimitDialogState extends State<_SpeedLimitDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  static const _presets = <(String, String)>[
    ('不限速', '0'),
    ('1 MB/s', '1MB/s'),
    ('5 MB/s', '5MB/s'),
    ('10 MB/s', '10MB/s'),
    ('20 MB/s', '20MB/s'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(String value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = context.read<DownloadController>();
    final error = await controller.setGlobalLimit(value);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('限速失败:$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
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
                      color: AppColors.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: const Icon(Icons.speed_rounded,
                        color: AppColors.accent, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    '全局下载限速',
                    style: TextStyle(
                      color: AppColors.foreground,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final preset in _presets)
                    _PresetChip(
                      label: preset.$1,
                      onTap: _busy ? null : () => _apply(preset.$2),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '自定义(例:2MB/s、500KB/s)',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.glassFill,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.glassBorderSoft),
                ),
                child: TextField(
                  controller: _controller,
                  style: TextStyle(
                      color: AppColors.foreground, fontSize: 14),
                  cursorColor: AppColors.accent,
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _apply(v.trim());
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    hintText: '输入速度…',
                    hintStyle:
                        TextStyle(color: AppColors.subtle, fontSize: 14),
                    border: InputBorder.none,
                  ),
                ),
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
                    label: '应用',
                    icon: Icons.check_rounded,
                    primary: true,
                    busy: _busy,
                    onPressed: () {
                      final value = _controller.text.trim();
                      if (value.isNotEmpty) _apply(value);
                    },
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

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.glassBorderSoft),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
