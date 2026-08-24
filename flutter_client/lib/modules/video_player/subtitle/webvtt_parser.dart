class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

Duration? _parseVttTimestamp(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  int hours = 0;
  int minutes = 0;
  double seconds = 0;
  if (parts.length == 3) {
    hours = int.tryParse(parts[0]) ?? 0;
    minutes = int.tryParse(parts[1]) ?? 0;
    seconds = double.tryParse(parts[2].replaceAll(',', '.')) ?? 0;
  } else {
    minutes = int.tryParse(parts[0]) ?? 0;
    seconds = double.tryParse(parts[1].replaceAll(',', '.')) ?? 0;
  }
  if (hours < 0 || minutes < 0 || seconds < 0) return null;
  final totalMs = (hours * 3600 * 1000) +
      (minutes * 60 * 1000) +
      (seconds * 1000).round();
  return Duration(milliseconds: totalMs);
}

List<SubtitleCue> parseWebVtt(String vttText) {
  final lines = vttText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final cues = <SubtitleCue>[];

  int i = 0;
  // Skip BOM and header
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  if (i < lines.length) {
    final first = lines[i].trimLeft();
    if (first.startsWith('\uFEFF')) {
      lines[i] = first.substring(1);
    }
  }
  if (i < lines.length && lines[i].trim().toUpperCase().startsWith('WEBVTT')) {
    i++;
  }

  while (i < lines.length) {
    // Skip empty lines
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    if (i >= lines.length) break;

    // Skip NOTE/STYLE/REGION blocks
    final head = lines[i].trim();
    if (head.startsWith('NOTE') || head.startsWith('STYLE') || head.startsWith('REGION')) {
      i++;
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        i++;
      }
      continue;
    }

    // Optional cue identifier
    String timeLine = lines[i];
    if (!timeLine.contains('-->')) {
      i++;
      if (i >= lines.length) break;
      timeLine = lines[i];
    }

    final arrow = timeLine.indexOf('-->');
    if (arrow == -1) {
      i++;
      continue;
    }
    final left = timeLine.substring(0, arrow).trim();
    final rightPart = timeLine.substring(arrow + 3).trim();
    final right = rightPart.split(RegExp(r'\s+'))[0].trim();

    final start = _parseVttTimestamp(left);
    final end = _parseVttTimestamp(right);
    i++;
    if (start == null || end == null) {
      // skip cue text lines until blank
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        i++;
      }
      continue;
    }

    final buf = StringBuffer();
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      buf.write(lines[i]);
      i++;
    }
    final text = _formatCueText(buf.toString().trim());
    if (text.isNotEmpty && end > start) {
      cues.add(SubtitleCue(start: start, end: end, text: text));
    }
  }

  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

/// Find active cue using binary search. `cues` must be sorted by start time.
SubtitleCue? findActiveCue(List<SubtitleCue> cues, Duration position) {
  if (cues.isEmpty) return null;
  int lo = 0;
  int hi = cues.length - 1;
  int best = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final c = cues[mid];
    if (c.start <= position) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (best < 0) return null;
  final c = cues[best];
  if (position >= c.start && position <= c.end) return c;
  return null;
}

/// ffmpeg WebVTT 常带 `<br>`、`<font>` 等标签；客户端叠层需转成纯文本。
String _formatCueText(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  s = s.replaceAll(RegExp(r'\{[^}]*\}'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return s.trim();
}

