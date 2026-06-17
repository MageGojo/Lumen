import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/geo_locator.dart';
import '../../state/api_tools_controller.dart';

class ApiInsightsPanel extends StatefulWidget {
  const ApiInsightsPanel({super.key});

  @override
  State<ApiInsightsPanel> createState() => _ApiInsightsPanelState();
}

class _ApiInsightsPanelState extends State<ApiInsightsPanel> {
  // Empty by default; the user's IP location fills in the weather automatically.
  final _cityController = TextEditingController();
  String? _detectedLngLat;
  String? _detectedCity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    final controller = context.read<ApiToolsController>();
    if (controller.weatherResult == null) {
      // Default to the user's IP-based location instead of a fixed city.
      final place = await GeoLocator.detect();
      if (!mounted) return;
      _detectedLngLat = place?.lngLat;
      _detectedCity = place?.city;
      if (_detectedCity != null && _detectedCity!.isNotEmpty) {
        _cityController.text = _detectedCity!;
      }
      await _fetchWeather();
    }
    if (controller.hitokotoResult == null) {
      await controller.fetchHitokoto();
    }
  }

  Future<void> _refreshWeather() => _fetchWeather();

  /// Honours a manually typed city; otherwise uses the detected coordinates,
  /// falling back to a default city only if geolocation failed.
  Future<void> _fetchWeather() {
    final typedCity = _cityController.text.trim();
    // Prefer precise coordinates while the field still shows the detected city;
    // only switch to a city-name query if the user typed a different place.
    final usingDetected =
        _detectedLngLat != null && (typedCity.isEmpty || typedCity == _detectedCity);
    final String city;
    final String location;
    if (usingDetected) {
      city = '';
      location = _detectedLngLat!;
    } else if (typedCity.isNotEmpty) {
      city = typedCity;
      location = '';
    } else {
      city = '北京';
      location = '';
    }
    return context.read<ApiToolsController>().fetchWeather(
      type: 'weather',
      city: city,
      location: location,
      alert: true,
      days: 3,
      hours: 24,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ApiToolsController>();

    return GlassPanel(
      radius: AppRadii.xl,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _WeatherCard(
                  cityController: _cityController,
                  onRefresh: controller.busy ? null : _refreshWeather,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _HitokotoCard(
                  onRefresh: controller.busy
                      ? null
                      : () =>
                            context.read<ApiToolsController>().fetchHitokoto(),
                ),
              ),
            ],
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _InlineError(message: controller.errorMessage!),
          ],
        ],
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  final TextEditingController cityController;
  final VoidCallback? onRefresh;

  const _WeatherCard({required this.cityController, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ApiToolsController>();
    final data = _dataOf(controller.weatherResult);
    final summary = _read(data, ['summary']);
    final location = _read(data, ['location']);
    final loading = controller.isBusy(ApiToolKind.weather);

    return _EmbeddedCard(
      icon: Icons.cloud_rounded,
      color: AppColors.info,
      title: '当前天气',
      trailing: SizedBox(
        width: 120,
        child: _MiniInput(
          controller: cityController,
          hintText: '自动定位',
          onSubmitted: (_) => onRefresh?.call(),
        ),
      ),
      child: loading
          ? const _LoadingLine(label: '正在更新天气…')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_text(_read(location, ['city']), fallback: cityController.text)} · ${_text(_read(summary, ['skycon']), fallback: '天气未知')}',
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${_text(_read(summary, ['temperature']))} ℃  体感 ${_text(_read(summary, ['apparent_temperature']))} ℃  AQI ${_text(_read(summary, ['air_quality', 'aqi']))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _text(
                    _read(data, ['forecast_keypoint']),
                    fallback: '点击刷新获取天气摘要',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.subtle, fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: _MiniAction(
                    label: '刷新',
                    icon: Icons.refresh_rounded,
                    onTap: onRefresh,
                  ),
                ),
              ],
            ),
    );
  }
}

class _HitokotoCard extends StatelessWidget {
  final VoidCallback? onRefresh;

  const _HitokotoCard({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ApiToolsController>();
    final data = _dataOf(controller.hitokotoResult);
    final loading = controller.isBusy(ApiToolKind.hitokoto);

    return _EmbeddedCard(
      icon: Icons.format_quote_rounded,
      color: AppColors.accent,
      title: '随机一言',
      child: loading
          ? const _LoadingLine(label: '正在抽取一言…')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  '“${_text(_read(data, ['hitokoto']), fallback: '点击刷新获取一句话')}”',
                  maxLines: 2,
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${_text(_read(data, ['from_who']), fallback: '佚名')} · ${_text(_read(data, ['from']), fallback: '未知出处')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: _MiniAction(
                    label: '换一句',
                    icon: Icons.auto_awesome_rounded,
                    onTap: onRefresh,
                  ),
                ),
              ],
            ),
    );
  }
}

class _EmbeddedCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final Widget child;
  final Widget? trailing;

  const _EmbeddedCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 176,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.backgroundDeep.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SectionLabel(icon: icon, color: color, label: title),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(child: child),
        ],
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

class _MiniInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;

  const _MiniInput({
    required this.controller,
    required this.hintText,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.glassBorderSoft),
      ),
      child: TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        style: TextStyle(color: AppColors.foreground, fontSize: 12.5),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: hintText,
          hintStyle: TextStyle(color: AppColors.subtle, fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _MiniAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_MiniAction> createState() => _MiniActionState();
}

class _MiniActionState extends State<_MiniAction> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovering && enabled
                ? AppColors.accent.withValues(alpha: 0.14)
                : AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: _hovering && enabled
                  ? AppColors.accent.withValues(alpha: 0.30)
                  : AppColors.glassBorderSoft,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: AppColors.accent),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(
                  color: AppColors.foreground,
                  fontSize: 12,
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

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: AppColors.warning, fontSize: 12),
    );
  }
}

Map<String, dynamic> _dataOf(Map<String, dynamic>? result) {
  final data = result?['data'];
  return data is Map<String, dynamic> ? data : (result ?? const {});
}

Object? _read(Object? source, List<Object> path) {
  Object? current = source;
  for (final segment in path) {
    if (current is Map) {
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
}

String _text(Object? value, {String fallback = '--'}) {
  if (value == null) return fallback;
  if (value is String) return value.trim().isEmpty ? fallback : value;
  return '$value';
}
