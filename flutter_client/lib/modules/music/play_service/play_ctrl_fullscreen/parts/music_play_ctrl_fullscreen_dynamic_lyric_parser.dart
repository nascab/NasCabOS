import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_lyric/core/lyric_parse.dart';

class MusicPlayCtrlFullScreenDynamicLyricParser {
  static final RegExp _wordTimeTagRegExp = RegExp(
    r'<(\d{1,}:\d{2})(?:\.(\d{1,3}))?>',
  );
  static final RegExp _metaTagRegExp = RegExp(r'^\[(\D[^:]*):(.*?)\]\s*$');

  static LyricModel? tryParse(String lyric) {
    if (!_supportsWordTimeline(lyric)) return null;
    final tags = <String, String>{};
    final lines = <LyricLine>[];

    for (final rawLine in lyric.split(RegExp(r'\r?\n'))) {
      final trimmedLine = rawLine.trimRight();
      if (trimmedLine.trim().isEmpty) continue;

      final tagMatch = _metaTagRegExp.firstMatch(trimmedLine.trim());
      if (tagMatch != null) {
        tags[tagMatch.group(1)!.trim()] = tagMatch.group(2)!.trim();
        continue;
      }

      final lrcLine = LrcParser.extractLine(trimmedLine);
      if (lrcLine == null) continue;

      for (final start in lrcLine.durations) {
        lines.add(_buildLine(start, lrcLine.text));
      }
    }

    if (lines.isEmpty) return null;
    lines.sort((a, b) => a.start.compareTo(b.start));
    return LyricModel(tags: tags, lines: _mergeTranslationLines(lines));
  }

  static bool _supportsWordTimeline(String lyric) {
    for (final rawLine in lyric.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final lrcLine = LrcParser.extractLine(line);
      if (lrcLine == null) continue;
      if (_wordTimeTagRegExp.hasMatch(lrcLine.text)) return true;
    }
    return false;
  }

  static LyricLine _buildLine(Duration start, String content) {
    final matches = _wordTimeTagRegExp.allMatches(content).toList();
    if (matches.isEmpty) {
      return LyricLine(start: start, text: content);
    }

    final words = <LyricWord>[];
    final buffer = StringBuffer();
    var cursor = 0;
    var segmentStart = start;

    for (final match in matches) {
      final nextStart = _parseDuration(match.group(1)!, match.group(2));
      if (match.start > cursor) {
        final text = content.substring(cursor, match.start);
        if (text.isNotEmpty) {
          buffer.write(text);
          words.add(LyricWord(text: text, start: segmentStart, end: nextStart));
        }
      }
      segmentStart = nextStart;
      cursor = match.end;
    }

    if (cursor < content.length) {
      final text = content.substring(cursor);
      if (text.isNotEmpty) {
        buffer.write(text);
        words.add(LyricWord(text: text, start: segmentStart));
      }
    }

    final text = buffer.toString();
    return LyricLine(
      start: start,
      end: words.isEmpty ? null : words.last.end,
      text: text.isEmpty ? content.replaceAll(_wordTimeTagRegExp, '') : text,
      words: words.isEmpty ? null : words,
    );
  }

  static List<LyricLine> _mergeTranslationLines(List<LyricLine> lines) {
    final merged = <LyricLine>[];
    var index = 0;

    while (index < lines.length) {
      final line = lines[index];
      final nextIndex = index + 1;
      if (nextIndex < lines.length && lines[nextIndex].start == line.start) {
        final translation = lines[nextIndex].text.trim();
        merged.add(
          LyricLine(
            start: line.start,
            end: line.end,
            text: line.text,
            words: line.words,
            translation: translation.isEmpty ? null : translation,
          ),
        );
        index += 2;
        continue;
      }

      merged.add(line);
      index++;
    }

    return merged;
  }

  static Duration _parseDuration(String minuteSecond, String? fraction) {
    final parts = minuteSecond.split(':');
    final minutes = int.parse(parts[0]);
    final seconds = int.parse(parts[1]);
    final milliseconds = int.parse((fraction ?? '0').padRight(3, '0'));
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }
}
