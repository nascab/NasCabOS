class FormatUtil {
  static String formatDurationSeconds(int seconds, {bool autoPadZero = false}) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;

    String maybePad(int v) =>
        autoPadZero ? v.toString().padLeft(2, '0') : v.toString();
    String twoDigits(int v) => v.toString().padLeft(2, '0');

    if (h > 0) {
      final hh = autoPadZero ? h.toString().padLeft(2, '0') : h.toString();
      return '$hh:${twoDigits(m)}:${twoDigits(sec)}';
    }
    return '${maybePad(m)}:${twoDigits(sec)}';
  }

  static String formatDuration(Duration duration, {bool autoPadZero = false}) {
    return formatDurationSeconds(duration.inSeconds, autoPadZero: autoPadZero);
  }
}
