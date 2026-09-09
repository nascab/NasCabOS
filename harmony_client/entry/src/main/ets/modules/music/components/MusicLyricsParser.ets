/**
 * 音乐歌词视图（对齐 Flutter flutter_lyric LyricView + DynamicLyricView）：
 * - LRC 逐行歌词：滚动定位当前行（居中），点击行跳转进度
 * - 逐字歌词（<mm:ss.xx> 词级时间标签）：当前行按词渐亮（easeOut）
 * - 同时间标签的下一行作为翻译行合并显示
 */

export class LyricWordSpan {
  text: string = '';
  start: number = 0;
  /** 结束时间（undefined 表示持续到行尾） */
  end: number = -1;
}

export class ParsedLyricLine {
  timeMs: number = 0;
  text: string = '';
  words: LyricWordSpan[] | undefined = undefined;
  translation: string = '';
}

const RE_TIME: RegExp = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
const RE_WORD: RegExp = /<(\d{1,}:\d{2})(?:\.(\d{1,3}))?>/g;
const RE_META: RegExp = /^\[[^0-9\]][^:]*:.*\]$/;

function parseTagMs(minStr: string, secStr: string, fracStr: string | undefined): number {
  const min = parseInt(minStr, 10);
  const sec = parseInt(secStr, 10);
  let frac = 0;
  if (fracStr !== undefined) {
    const digits = fracStr.length;
    const v = parseInt(fracStr, 10);
    frac = digits === 1 ? v * 100 : digits === 2 ? v * 10 : v;
  }
  return min * 60000 + sec * 1000 + frac;
}

function parseWordTagMs(minSec: string, frac: string | undefined): number {
  const parts = minSec.split(':');
  const min = parseInt(parts[0], 10);
  const sec = parseInt(parts[1], 10);
  const ms = parseInt((frac ?? '0').padEnd(3, '0'), 10);
  return min * 60000 + sec * 1000 + ms;
}

/** 词级高亮进度（对齐 resolveMusicPlayCtrlFullScreenDynamicLyricHighlightProgress） */
export function wordHighlightProgress(posMs: number, start: number, end: number, nextStart: number): number {
  const resolvedEnd = end >= 0 ? end : (nextStart >= 0 ? nextStart : start + 450);
  if (posMs < start) {
    return 0;
  }
  if (resolvedEnd <= start) {
    return posMs >= start ? 1 : 0;
  }
  if (posMs >= resolvedEnd) {
    return 1;
  }
  const t = (posMs - start) / (resolvedEnd - start);
  // easeOut
  return 1 - (1 - Math.min(Math.max(t, 0), 1)) * (1 - Math.min(Math.max(t, 0), 1));
}

function buildLineWithWords(lineStart: number, content: string): ParsedLyricLine {
  const matches: RegExpExecArray[] = [];
  RE_WORD.lastIndex = 0;
  let m = RE_WORD.exec(content);
  while (m !== null) {
    matches.push(m);
    m = RE_WORD.exec(content);
  }
  const line = new ParsedLyricLine();
  line.timeMs = lineStart;
  if (matches.length === 0) {
    line.text = content;
    return line;
  }

  const words: LyricWordSpan[] = [];
  let text = '';
  let cursor = 0;
  let segmentStart = lineStart;
  for (const match of matches) {
    const nextStart = parseWordTagMs(match[1], match[2]);
    if (match.index > cursor) {
      const t = content.substring(cursor, match.index);
      if (t.length > 0) {
        const w = new LyricWordSpan();
        w.text = t;
        w.start = segmentStart;
        w.end = nextStart;
        words.push(w);
        text += t;
      }
    }
    segmentStart = nextStart;
    cursor = match.index + match[0].length;
  }
  if (cursor < content.length) {
    const t = content.substring(cursor);
    if (t.length > 0) {
      const w = new LyricWordSpan();
      w.text = t;
      w.start = segmentStart;
      w.end = -1;
      words.push(w);
      text += t;
    }
  }
  line.text = text.length > 0 ? text : content.replace(RE_WORD, '');
  line.words = words;
  return line;
}

/** 解析 LRC（含逐字时间标签与翻译合并），失败/无有效行返回空数组 */
export function parseLyricText(lrcText: string): ParsedLyricLine[] {
  const hasWordTimeline = lrcText.split('\n').some((raw: string): boolean => {
    const line = raw.trim();
    if (line.length === 0) {
      return false;
    }
    RE_WORD.lastIndex = 0;
    return RE_WORD.test(line);
  });

  const lines: ParsedLyricLine[] = [];
  const rawLines = lrcText.split('\n');
  for (const raw of rawLines) {
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      continue;
    }
    if (RE_META.test(trimmed)) {
      continue;
    }
    // 收集行级时间标签
    const times: number[] = [];
    RE_TIME.lastIndex = 0;
    let tm = RE_TIME.exec(trimmed);
    while (tm !== null) {
      times.push(parseTagMs(tm[1], tm[2], tm[3]));
      tm = RE_TIME.exec(trimmed);
    }
    if (times.length === 0) {
      continue;
    }
    const content = trimmed.replace(RE_TIME, '').trim();
    if (content.length === 0) {
      continue;
    }
    for (const t of times) {
      if (hasWordTimeline) {
        lines.push(buildLineWithWords(t, content));
      } else {
        const line = new ParsedLyricLine();
        line.timeMs = t;
        line.text = content;
        lines.push(line);
      }
    }
  }
  if (lines.length === 0) {
    return [];
  }
  lines.sort((a: ParsedLyricLine, b: ParsedLyricLine): number => a.timeMs - b.timeMs);

  // 同时间标签的下一行作为翻译合并（对齐 _mergeTranslationLines 成对处理）
  const merged: ParsedLyricLine[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const next = i + 1 < lines.length ? lines[i + 1] : undefined;
    if (next !== undefined && next.timeMs === line.timeMs) {
      const tr = next.text.trim();
      line.translation = tr;
      merged.push(line);
      i += 2;
      continue;
    }
    merged.push(line);
    i += 1;
  }
  return merged;
}

export function findActiveLyricIndex(lines: ParsedLyricLine[], posMs: number): number {
  let idx = -1;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].timeMs <= posMs) {
      idx = i;
    } else {
      break;
    }
  }
  return idx;
}
