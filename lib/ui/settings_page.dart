import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/glass.dart';
import '../core/utils/extension_installer.dart';
import '../core/utils/url_opener.dart';
import '../state/api_tools_controller.dart';
import '../state/settings_controller.dart';
import 'widgets/aurora_background.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _endpointController;
  late final TextEditingController _portController;
  late final TextEditingController _userAgentController;
  late final TextEditingController _headersController;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>();
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _endpointController = TextEditingController(text: settings.parseBaseUrl);
    _portController =
        TextEditingController(text: settings.bridgePort.toString());
    _userAgentController = TextEditingController(text: settings.userAgent);
    _headersController =
        TextEditingController(text: settings.customHeadersText);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _endpointController.dispose();
    _portController.dispose();
    _userAgentController.dispose();
    _headersController.dispose();
    super.dispose();
  }

  void _savePort(String value) {
    final port = int.tryParse(value.trim());
    if (port != null) context.read<SettingsController>().setBridgePort(port);
  }

  void _saveApiKey(String value) {
    context.read<SettingsController>().setApiKey(value);
    context.read<ApiToolsController>().setApiKey(value);
  }

  void _saveEndpoint(String value) {
    final settings = context.read<SettingsController>();
    settings.setParseBaseUrl(value);
    context.read<ApiToolsController>().setBaseUrl(settings.parseBaseUrl);
  }

  void _saveUserAgent(String value) =>
      context.read<SettingsController>().setUserAgent(value);

  void _saveHeaders(String value) =>
      context.read<SettingsController>().setCustomHeadersFromText(value);

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final settings = context.watch<SettingsController>();
    final port = settings.bridgePort;
    final dupCheck = settings.duplicateCheckEnabled;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: AuroraBackground(animate: !reduceMotion)),
          Column(
            children: [
              _TopBar(onBack: () => Navigator.of(context).maybePop()),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SettingsSection(
                            icon: Icons.api_rounded,
                            color: AppColors.info,
                            title: 'Apizero 解析',
                            children: [
                              _FieldLabel(
                                label: 'API Key',
                                hint: '用于下载栏自动解析视频 / 图文分享链接',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _GlassField(
                                controller: _apiKeyController,
                                hintText: '粘贴 Apizero API Key',
                                icon: Icons.key_rounded,
                                obscureText: _obscureKey,
                                onChanged: _saveApiKey,
                                suffix: _EyeToggle(
                                  obscured: _obscureKey,
                                  onTap: () => setState(
                                    () => _obscureKey = !_obscureKey,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              _LinkHint(
                                text: '没有 Key?前往 apizero.cn 获取',
                                onTap: () =>
                                    UrlOpener.open('https://apizero.cn'),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _FieldLabel(
                                label: '解析接口地址',
                                hint: '可切换到自建 / 兼容的解析服务',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _GlassField(
                                controller: _endpointController,
                                hintText: SettingsController.defaultParseBaseUrl,
                                icon: Icons.link_rounded,
                                onChanged: _saveEndpoint,
                              ),
                              const SizedBox(height: 6),
                              _ResetEndpoint(
                                onReset: () {
                                  _endpointController.text =
                                      SettingsController.defaultParseBaseUrl;
                                  _saveEndpoint(
                                    SettingsController.defaultParseBaseUrl,
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _SettingsSection(
                            icon: Icons.extension_rounded,
                            color: AppColors.accent,
                            title: '浏览器扩展(嗅探下载)',
                            children: [
                              _AddressRow(
                                address: 'http://127.0.0.1:$port',
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              const _ExtensionActions(),
                              const SizedBox(height: AppSpacing.lg),
                              _FieldLabel(
                                label: '本地桥端口',
                                hint: '扩展通过该端口把链接发给应用(修改后需重启应用)',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _GlassField(
                                controller: _portController,
                                hintText:
                                    SettingsController.defaultBridgePort
                                        .toString(),
                                icon: Icons.lan_rounded,
                                onChanged: _savePort,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              const _InstructionBlock(
                                steps: [
                                  '在 Chrome 打开 chrome://extensions',
                                  '右上角开启「开发者模式」',
                                  '点「加载已解压的扩展程序」,选择项目里的 browser_extension 目录',
                                  '在网页上播放/打开媒体,点扩展图标即可发送到本应用下载',
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _SettingsSection(
                            icon: Icons.file_copy_rounded,
                            color: AppColors.warning,
                            title: '下载',
                            children: [
                              _ToggleRow(
                                label: '重复下载检测',
                                hint: '下载前检查目录是否已有同名 / 大小相同的文件,'
                                    '命中则弹窗确认(默认不下载)',
                                value: dupCheck,
                                onChanged: (v) => context
                                    .read<SettingsController>()
                                    .setDuplicateCheckEnabled(v),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _SettingsSection(
                            icon: Icons.travel_explore_rounded,
                            color: AppColors.info,
                            title: '下载请求(UA / 请求头)',
                            children: [
                              _FieldLabel(
                                label: 'User-Agent',
                                hint: '部分站点需特定 UA 才能下载;留空用引擎默认。'
                                    '设置后这些下载自动走 aria2 引擎',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _GlassField(
                                controller: _userAgentController,
                                hintText: '留空 = 默认;或粘贴自定义 User-Agent',
                                icon: Icons.computer_rounded,
                                onChanged: _saveUserAgent,
                              ),
                              const SizedBox(height: 6),
                              _LinkHint(
                                text: '使用浏览器(Chrome)UA',
                                onTap: () {
                                  _userAgentController.text =
                                      SettingsController.chromeUserAgent;
                                  _saveUserAgent(
                                    SettingsController.chromeUserAgent,
                                  );
                                },
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _FieldLabel(
                                label: '自定义请求头',
                                hint: '每行一个「名称: 值」,如 Cookie / Authorization / Referer',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _GlassField(
                                controller: _headersController,
                                hintText:
                                    'Cookie: a=1; b=2\nReferer: https://example.com',
                                icon: Icons.list_alt_rounded,
                                minLines: 3,
                                maxLines: 6,
                                onChanged: _saveHeaders,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _SettingsSection(
                            icon: Icons.palette_rounded,
                            color: AppColors.auroraViolet,
                            title: '外观',
                            children: const [
                              _FieldLabel(
                                label: '主题',
                                hint: '浅色 / 深色 / 跟随系统',
                              ),
                              SizedBox(height: AppSpacing.sm),
                              _ThemeSelector(),
                            ],
                          ),
                        ],
                      ),
                    ),
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

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;
  const _TopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: DragToMoveArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 82, right: AppSpacing.lg),
          child: Row(
            children: [
              _BackButton(onTap: onBack),
              const SizedBox(width: AppSpacing.md),
              Text(
                '设置',
                style: TextStyle(
                  color: AppColors.foreground,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatefulWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hovering ? AppColors.glassFillStrong : AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: _hovering
                  ? AppColors.glassHighlight
                  : AppColors.glassBorderSoft,
            ),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 18,
            color: AppColors.foreground,
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: AppRadii.xl,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(color: color.withValues(alpha: 0.24)),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: TextStyle(
                  color: AppColors.foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final String hint;
  const _FieldLabel({required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.foreground,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: TextStyle(color: AppColors.subtle, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final bool obscureText;
  final ValueChanged<String> onChanged;
  final Widget? suffix;
  final int minLines;
  final int maxLines;

  const _GlassField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.onChanged,
    this.obscureText = false,
    this.suffix,
    this.minLines = 1,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final multiline = maxLines > 1;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              onChanged: onChanged,
              minLines: obscureText ? 1 : minLines,
              maxLines: obscureText ? 1 : maxLines,
              keyboardType:
                  multiline ? TextInputType.multiline : TextInputType.text,
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 13,
                height: multiline ? 1.5 : null,
                fontFamily: multiline ? 'Menlo' : null,
              ),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                prefixIcon: Icon(icon, color: AppColors.muted, size: 18),
                hintText: hintText,
                hintStyle: TextStyle(
                  color: AppColors.subtle,
                  fontSize: 13,
                  height: multiline ? 1.5 : null,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 14,
                ),
              ),
            ),
          ),
          if (suffix != null) ...[
            suffix!,
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _EyeToggle extends StatelessWidget {
  final bool obscured;
  final VoidCallback onTap;
  const _EyeToggle({required this.obscured, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(
          obscured
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          size: 18,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

class _LinkHint extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _LinkHint({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.accent,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ResetEndpoint extends StatelessWidget {
  final VoidCallback onReset;
  const _ResetEndpoint({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onReset,
        child: Text(
          '恢复默认接口',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<SettingsController>().themeMode;
    void set(ThemeMode m) => context.read<SettingsController>().setThemeMode(m);
    return Row(
      children: [
        _ThemeOption(
          label: '跟随系统',
          icon: Icons.brightness_auto_rounded,
          selected: mode == ThemeMode.system,
          onTap: () => set(ThemeMode.system),
        ),
        const SizedBox(width: AppSpacing.sm),
        _ThemeOption(
          label: '浅色',
          icon: Icons.light_mode_rounded,
          selected: mode == ThemeMode.light,
          onTap: () => set(ThemeMode.light),
        ),
        const SizedBox(width: AppSpacing.sm),
        _ThemeOption(
          label: '深色',
          icon: Icons.dark_mode_rounded,
          selected: mode == ThemeMode.dark,
          onTap: () => set(ThemeMode.dark),
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.16)
                  : AppColors.glassFill,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.4)
                    : AppColors.glassBorderSoft,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.accent : AppColors.muted,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppColors.foreground : AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _ToggleRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: TextStyle(
                      color: AppColors.subtle,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _GlassSwitch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _GlassSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 46,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value
              ? AppColors.accent.withValues(alpha: 0.85)
              : AppColors.glassFillStrong,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: value
                ? AppColors.accent.withValues(alpha: 0.6)
                : AppColors.glassBorder,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value ? Colors.white : AppColors.muted,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final String address;
  const _AddressRow({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, size: 16, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '本地桥',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: SelectableText(
              address,
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 13,
                fontFamily: 'Menlo',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionBlock extends StatelessWidget {
  final List<String> steps;
  const _InstructionBlock({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.backgroundDeep.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == steps.length - 1 ? 0 : AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ExtensionActions extends StatefulWidget {
  const _ExtensionActions();

  @override
  State<_ExtensionActions> createState() => _ExtensionActionsState();
}

class _ExtensionActionsState extends State<_ExtensionActions> {
  bool _busy = false;

  void _toast(String message, {required bool ok}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface.withValues(alpha: 0.96),
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            side: BorderSide(
              color: (ok ? AppColors.accent : AppColors.destructive)
                  .withValues(alpha: 0.5),
            ),
          ),
          content: Text(
            message,
            style: TextStyle(color: AppColors.foreground),
          ),
        ),
      );
  }

  Future<void> _install() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final path = await ExtensionInstaller.materialize();
    await Clipboard.setData(ClipboardData(text: path));
    await ExtensionInstaller.openExtensionsPage();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.clearSnackBars();
    _toast('扩展已就绪,目录已复制。在扩展页开启「开发者模式」→「加载已解压的扩展程序」并粘贴路径', ok: true);
  }

  Future<void> _quickLaunch() async {
    if (_busy) return;
    setState(() => _busy = true);
    final path = await ExtensionInstaller.materialize();
    final ok = await ExtensionInstaller.launchChromeWithExtension(path);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(
      ok ? '已用独立配置启动 Chrome 并加载扩展' : '启动 Chrome 失败,请改用上面的方式手动加载',
      ok: ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _PillButton(
                label: '一键安装扩展',
                icon: Icons.download_rounded,
                primary: true,
                busy: _busy,
                onTap: _install,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _PillButton(
                label: 'Chrome 直接试用',
                icon: Icons.open_in_new_rounded,
                onTap: _busy ? null : _quickLaunch,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Chrome 出于安全不支持非商店「无感安装」;一键安装会打开扩展页并复制目录,粘贴即可加载。',
          style: TextStyle(color: AppColors.subtle, fontSize: 11),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final bool busy;
  final VoidCallback? onTap;

  const _PillButton({
    required this.label,
    required this.icon,
    this.primary = false,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary
                ? AppColors.accent.withValues(alpha: enabled ? 0.16 : 0.06)
                : AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: primary
                  ? AppColors.accent.withValues(alpha: enabled ? 0.32 : 0.12)
                  : AppColors.glassBorderSoft,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
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
                  icon,
                  size: 15,
                  color: enabled ? AppColors.accent : AppColors.subtle,
                ),
              const SizedBox(width: 6),
              Text(
                label,
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
