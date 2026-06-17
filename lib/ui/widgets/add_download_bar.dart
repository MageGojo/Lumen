import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/folder_picker.dart';
import '../../core/utils/link_classifier.dart';
import '../../state/api_tools_controller.dart';
import '../../state/download_controller.dart';
import '../../state/settings_controller.dart';
import 'duplicate_dialog.dart';
import 'glass_button.dart';

/// Top input row: paste a URL, pick a destination, and add the download.
class AddDownloadBar extends StatefulWidget {
  const AddDownloadBar({super.key});

  @override
  State<AddDownloadBar> createState() => _AddDownloadBarState();
}

class _AddDownloadBarState extends State<AddDownloadBar> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _uaController = TextEditingController();
  final TextEditingController _headersController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _busy = false;
  bool _advancedOpen = false;

  @override
  void dispose() {
    _urlController.dispose();
    _uaController.dispose();
    _headersController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _busy) return;

    // Routing: supported share *pages* are parsed by Apizero first; magnet /
    // torrent and direct files (incl. .mp4/.m3u8) go straight to the download
    // engines (aria2 / Surge) via the controller.
    if (LinkClassifier.classify(url) == LinkRoute.share) {
      await _parseShare(url);
      return;
    }

    setState(() => _busy = true);
    final controller = context.read<DownloadController>();
    final settings = context.read<SettingsController>();
    // Per-add overrides (merged on top of the global defaults by the controller).
    final ua = _uaController.text.trim();
    final headers =
        SettingsController.parseHeadersText(_headersController.text);
    final outcome = await controller.addWithDuplicateCheck(
      url,
      userAgent: ua.isEmpty ? null : ua,
      headers: headers.isEmpty ? null : headers,
      checkEnabled: settings.duplicateCheckEnabled,
      onDuplicate: (report) => showDuplicateDialog(context, report),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome.cancelled) {
      _showSnack('已取消下载(目录中已存在该文件)', ok: true);
    } else if (outcome.ok) {
      _urlController.clear();
      _showSnack('已加入下载队列', ok: true);
    } else {
      _showSnack(outcome.error ?? '添加失败', ok: false);
    }
  }

  Future<void> _parseShare(String url) async {
    final settings = context.read<SettingsController>();
    final apiTools = context.read<ApiToolsController>();
    if (settings.apiKey.trim().isEmpty) {
      _showSnack('检测到分享链接,请先在设置里填写 Apizero API Key', ok: false);
      return;
    }
    apiTools.setApiKey(settings.apiKey);
    apiTools.setBaseUrl(settings.parseBaseUrl);

    setState(() => _busy = true);
    await apiTools.parseShareLink(url);
    if (!mounted) return;
    setState(() => _busy = false);
    // Result and errors are surfaced by VideoParsePanel below the bar.
    if (apiTools.videoError == null) {
      _urlController.clear();
    }
  }

  Future<void> _chooseDir() async {
    final dir = await FolderPicker.choose(prompt: '选择下载保存目录');
    if (dir != null && mounted) {
      context.read<DownloadController>().setDefaultOutputDir(dir);
    }
  }

  void _showSnack(String message, {required bool ok}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
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
                message,
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
    final controller = context.watch<DownloadController>();
    final dir = controller.defaultOutputDir;
    final dirName = (dir == null || dir.isEmpty)
        ? '下载目录'
        : dir.split('/').where((s) => s.isNotEmpty).last;

    return GlassPanel(
      radius: AppRadii.xl,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.glassFill,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.glassBorderSoft),
                  ),
                  child: TextField(
                    controller: _urlController,
                    focusNode: _focusNode,
                    style: TextStyle(
                      color: AppColors.foreground,
                      fontSize: 14,
                    ),
                    cursorColor: AppColors.accent,
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 14),
                      prefixIcon: Icon(Icons.link_rounded,
                          color: AppColors.muted, size: 19),
                      hintText: '粘贴下载链接,或视频 / 图文分享链接(自动解析)',
                      hintStyle:
                          TextStyle(color: AppColors.subtle, fontSize: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              _AdvancedToggle(
                open: _advancedOpen,
                active: _uaController.text.trim().isNotEmpty ||
                    _headersController.text.trim().isNotEmpty,
                onTap: () => setState(() => _advancedOpen = !_advancedOpen),
              ),
              const SizedBox(width: AppSpacing.md),
              _DirChip(name: dirName, fullPath: dir, onTap: _chooseDir),
              const SizedBox(width: AppSpacing.md),
              GlassButton(
                label: '添加',
                icon: Icons.add_rounded,
                primary: true,
                busy: _busy,
                onPressed: controller.isConnected ? _add : null,
              ),
            ],
          ),
          if (_advancedOpen) ...[
            const SizedBox(height: AppSpacing.md),
            _AdvancedFields(
              uaController: _uaController,
              headersController: _headersController,
              onChanged: () => setState(() {}),
            ),
          ],
        ],
      ),
    );
  }
}

/// Toggle chip that reveals per-download UA / header overrides. Glows when an
/// override is currently set.
class _AdvancedToggle extends StatelessWidget {
  final bool open;
  final bool active;
  final VoidCallback onTap;

  const _AdvancedToggle({
    required this.open,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final highlight = open || active;
    return Tooltip(
      message: '高级:本次下载的 UA / 请求头',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 11),
            decoration: BoxDecoration(
              color: highlight
                  ? AppColors.accent.withValues(alpha: 0.16)
                  : AppColors.glassFill,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: highlight
                    ? AppColors.accent.withValues(alpha: 0.4)
                    : AppColors.glassBorderSoft,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 17,
                  color: highlight ? AppColors.accent : AppColors.muted,
                ),
                if (active) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The per-download advanced override fields (UA + raw headers).
class _AdvancedFields extends StatelessWidget {
  final TextEditingController uaController;
  final TextEditingController headersController;
  final VoidCallback onChanged;

  const _AdvancedFields({
    required this.uaController,
    required this.headersController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '仅作用于本次下载;留空则用「设置」里的全局默认。设置后该下载走 aria2 引擎。',
            style: TextStyle(color: AppColors.subtle, fontSize: 11.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MiniField(
            controller: uaController,
            icon: Icons.computer_rounded,
            hintText: 'User-Agent(留空 = 全局默认)',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MiniField(
            controller: headersController,
            icon: Icons.list_alt_rounded,
            hintText: '请求头,每行「名称: 值」,如 Cookie: a=1',
            minLines: 2,
            maxLines: 5,
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String hintText;
  final int minLines;
  final int maxLines;
  final ValueChanged<String> onChanged;

  const _MiniField({
    required this.controller,
    required this.icon,
    required this.hintText,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final multiline = maxLines > 1;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassFillStrong,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 13),
            child: Icon(icon, size: 16, color: AppColors.muted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              minLines: minLines,
              maxLines: maxLines,
              keyboardType:
                  multiline ? TextInputType.multiline : TextInputType.text,
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 12.5,
                height: multiline ? 1.5 : null,
                fontFamily: multiline ? 'Menlo' : null,
              ),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hintText,
                hintStyle: TextStyle(color: AppColors.subtle, fontSize: 12.5),
                contentPadding:
                    const EdgeInsets.only(right: 10, top: 12, bottom: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirChip extends StatefulWidget {
  final String name;
  final String? fullPath;
  final VoidCallback onTap;

  const _DirChip({required this.name, required this.fullPath, required this.onTap});

  @override
  State<_DirChip> createState() => _DirChipState();
}

class _DirChipState extends State<_DirChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final chip = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 11),
          decoration: BoxDecoration(
            color: _hovering ? AppColors.glassFillStrong : AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: _hovering
                  ? AppColors.glassHighlight
                  : AppColors.glassBorderSoft,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_rounded,
                  size: 17, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  widget.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Tooltip(
      message: widget.fullPath ?? '点击选择下载保存目录',
      child: chip,
    );
  }
}
