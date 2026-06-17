import 'dart:math' as math;

/// Human-readable formatting helpers for sizes, speeds, durations.
class Formatters {
  const Formatters._();

  static const List<String> _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

  /// Formats a byte count, e.g. 2462055 -> "2.3 MB".
  static String bytes(num value, {int decimals = 1}) {
    if (value <= 0) return '0 B';
    final i = (math.log(value) / math.log(1024))
        .floor()
        .clamp(0, _units.length - 1);
    final scaled = value / math.pow(1024, i);
    final dec = i == 0 ? 0 : decimals;
    return '${scaled.toStringAsFixed(dec)} ${_units[i]}';
  }

  /// Formats a speed given in bytes/second, e.g. "5.2 MB/s".
  static String speed(num bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 B/s';
    return '${bytes(bytesPerSecond)}/s';
  }

  /// Formats an ETA given in seconds.
  static String eta(int seconds) {
    if (seconds <= 0) return '--';
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Formats a percent value (0-100) to an integer string with sign.
  static String percent(double value) => '${value.clamp(0, 100).round()}%';
}
